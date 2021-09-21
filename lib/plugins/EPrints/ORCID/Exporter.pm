package EPrints::ORCID::Exporter;

use strict;
use utf8;

# loop through a list of eprints and export them for a given user
# called from the ExportToOrcid screen
sub export_user_eprints
{
    my( $repo, $user, @eprints ) = @_;

    my $results = {
        total => 0,
    };

    foreach my $eprint ( @eprints )
    {
        my $result = _export_eprint_to_orcid( $repo, $user, $eprint );
        $results = _log_results( $result, $results );
        $results->{total} = $results->{total} + 1;
    }
    _display_results( $repo, $results );
}


# loop through all of the orcids for this eprint,
# check if they've given permission to export and if export for that user
# called when an eprint goes live or is changed in a relevant way
sub auto_export_eprint
{
    my( $repo, $eprint ) = @_;

    # TODO: Other orcids beyond creators!!!!
    my @creators_orcids = @{$eprint->value( "creators_orcid" )};

    my $results = {
        total => 0,
    };

    foreach my $creator_orcid( @creators_orcids )
    {
        my $user = EPrints::ORCID::Utils::user_with_orcid( $repo, $creator_orcid );
        if( defined $user && EPrints::ORCID::AdvanceUtils::check_permission( $user, "/activities/update" ) && $user->is_set( "orcid_auto_update" ) && $user->value( "orcid_auto_update" ) eq "TRUE" )
        {
            my $result = _export_eprint_to_orcid( $repo, $user, $eprint );
            $results = _log_results( $result, $results );
            $results->{total} = $results->{total} + 1;
        }
    }
    _display_results( $repo, $results );
}

sub _export_eprint_to_orcid
{
    my( $repo, $user, $eprint ) = @_;
  
    # Initialise some useful things
    my $putcode = undef;
    my $result = undef;
    my $work = _eprint_to_orcid_work( $repo, $eprint, $user );

    # first of all, is this going to be a POST or a PUT?
    # Use POST for unpublished and PUT with putcode for published records
    my @creators = @{ $eprint->value( "creators" ) };
    my $users_orcid = $user->value( "orcid" );
    my $method = "POST";

    foreach my $creator (@creators)
    {
        if( ($creator->{orcid} eq $users_orcid) && defined($creator->{putcode}) )
        {
            $putcode = $creator->{putcode};
            $method = "PUT";
            last;
        }
    }

    if( $method eq "POST")
    {
        $result = _post( $repo, $user, $work, $users_orcid, \@creators, $eprint );
        if( $result->is_success )
        {
            return "new";
        }
    }
    elsif( $method eq "PUT" )
    {
        $result = EPrints::ORCID::AdvanceUtils::write_orcid_record( $repo, $user, $method, "/work/$putcode", $work );
        if( $result->is_success )
        {
            return "update";
        }
    }

    if( $result->is_error ) # first check orcid error code
    {
        # Identify response code by parsing XML with ORCID namespace
        my $dom = XML::LibXML->load_xml( string => $result->content() );
        my $xpc = XML::LibXML::XPathContext->new( $dom );
        $xpc->registerNs( 'orcid_error', 'http://www.orcid.org/ns/error' );
        my($error_nodes) = $xpc->findnodes( '//orcid_error:error' );

        # get orcid error code
        my $error_code = $xpc->findvalue( './/orcid_error:error-code', $error_nodes );
        if( ( $error_code eq "9010" || $error_code eq "9016" ) && $method eq "PUT" )
        {
            # Error code 9010: The client application is not the source of the resource it is trying to access.
            # Therefore we should POST the record to add a new source to the ORCID profile
            # Error code 9016: The work has been removed from orcid.org since original export and so we need to POST it again
            delete $work->{"put-code"};
            $result = _post( $repo, $user, $work, $users_orcid, \@creators, $eprint );
            if( $result->is_success )
            {
                return "new";
            }
        }
        elsif( $error_code eq "9021" && $method eq "POST" )
        {
            # This record already exists in ORCID, but we've lost our PUT code for it - lets see if we can retrieve it
            my $new_putcode = undef;

            # first retrieve the external ids that we've got on record
            my %work_ids;
            foreach my $work_ext_id ( @{$work->{'external-ids'}->{'external-id'}} )
            {
                $work_ids{$work_ext_id->{'external-id-type'}} = $work_ext_id->{'external-id-value'};
            }

            # get all the works, including the different versions from different sources
            my $orcid_works = EPrints::ORCID::AdvanceUtils::read_orcid_works_all_sources( $repo, $user );
            foreach my $orcid_work ( @{$orcid_works} )
            {
                foreach my $work_item ( @{$orcid_work->{'work-summary'}} )
                {
                    my $ext_ids = $work_item->{'external-ids'}->{'external-id'};
                    my $match = 0;
                    foreach my $ext_id ( @$ext_ids )
                    {
                        if( exists $work_ids{$ext_id->{'external-id-type'}} && $work_ids{$ext_id->{'external-id-type'}} eq $ext_id->{'external-id-value'} )
                        {
                            $match = 1;
                            last;
                        }
                    }
                    if( $match )
                    {
                        # this is the work-summary we need, but which put-code do we need...
                    $new_putcode = $work_item->{'put-code'} if !defined $new_putcode; # get the first put-code we come across
                        if( $work_item->{'source'}->{'source-client-id'}->{'path'} eq $repo->config( "orcid_support_advance", "client_id" ) )
                        {
                            # this source came from the repository - this is the put-code we really want
                            $new_putcode = $work_item->{'put-code'};
                        }
                    }
                }
            }

            if( defined $new_putcode )
            {
                # update the put-code for the work we're trying to export
                my @new_creators;
                my $update = 0;
                foreach my $c ( @{$eprint->value( "creators" )} )
                {
                    my $new_c = $c;
                    if( $c->{orcid} eq $users_orcid ) # we have the matching user
                    {
                        $new_c->{putcode} = $new_putcode;
                        $update = 1;
                    }
                    push( @new_creators, $new_c );
                }
                if( $update )
                {
                    $eprint->{orcid_update} = 1;
                    $eprint->set_value( "creators", \@new_creators );
                    $eprint->commit;

                    # now we have an updated eprint with a new put code, try to PUT the record again
                    my $new_work = _eprint_to_orcid_work( $repo, $eprint, $user );
                    $result = EPrints::ORCID::AdvanceUtils::write_orcid_record( $repo, $user, "PUT", "/work/$new_putcode", $new_work );
                    if( $result->is_success )
                    {
                        return "update";
                    }
                }
            } # end new putcode
        } # end 90217 error - lost PUT Code       
    } # end initial result error

    if( $result->is_error ) # still getting an error or one we're not actively handling
    {
        # log the response message, break loop and continue with next eprint item
        my $error_message = $result->content();
        $repo->log( "[Event::ExportToOrcid::action_export]Failed to add or update " . $eprint->id .". Response from ORCID: $error_message\n" );
        return "fail";
    }    
} 

sub _eprint_to_orcid_work
{
    my( $repo, $eprint, $user ) = @_;

    my $work = { "title" => { "title" => { "value" => $eprint->get_value( "title" ) } } };

    $work->{"type"} = &{$repo->config( "orcid_support_advance", "work_type_to_eprint" )}( $eprint );

    # set journal title, if relevant
    if( $eprint->exists_and_set( "type" ) && $eprint->get_value( "type" ) eq "article" && $eprint->exists_and_set( "publication" ) )
    {
        $work->{"journal-title"} = $eprint->get_value( "publication" );
    }

    # add abstract, if relevant
    $work->{"short-description"} = _curtail_abstract( $eprint->get_value( "abstract" ) ) if $eprint->exists_and_set( "abstract" );

    # add citation
    my $bibtex_plugin = EPrints::Plugin::Export::BibTeX->new();
    $bibtex_plugin->{"session"} = $repo;
    $work->{"citation"} = {
        "citation-type" => "BIBTEX",
        "citation-value" => $bibtex_plugin->output_dataobj( $eprint ),
    };

    # publication date
    if( $eprint->exists_and_set( "date" ) )
    {
        $work->{"publication-date"} = {
            "year" => 0 + substr( $eprint->get_value( "date" ),0,4),
            "month" => length( $eprint->get_value( "date" )) >=7 ? 0 + substr( $eprint->get_value( "date" ),5,2) : undef,
            "day" => length( $eprint->get_value( "date" )) >=9 ? 0 + substr( $eprint->get_value( "date" ),8,2) : undef,
        }
    }

    # put-code
    my @creators = @{ $eprint->value( "creators" ) };
    foreach my $creator (@creators)
    {
        if( $creator->{orcid} eq $user->value( "orcid" ) )
        {
            $work->{"put-code"} = $creator->{putcode};
            last;
        }
    }

    # EPrint identifiers
    $work->{"external-ids"} = {"external-id" => [
        {
            "external-id-type" => "source-work-id",
            "external-id-value" => $eprint->get_value( "eprintid" ),
            "external-id-relationship" => "SELF",
        },
        {
            "external-id-type" => "uri",
            "external-id-value" => $eprint->get_url,
            "external-id-url" => { "value" => $eprint->get_url },
            "external-id-relationship" => "SELF",
        },
    ]};

    # URNs
    my $urn = undef;
    if( $eprint->exists_and_set( "urn" ) && $eprint->get_value( "urn" ) =~ m'(^urn:[a-z0-9][a-z0-9-]{0,31}:[a-z0-9()+,\-.:=@;$_!*\'%/?#]+$)' )
    {
        $urn = $1;
    }
    if( !defined( $urn ) && $eprint->exists_and_set( "id_number" ) && $eprint->get_value( "id_number" ) =~ m'(^urn:[a-z0-9][a-z0-9-]{0,31}:[a-z0-9()+,\-.:=@;$_!*\'%/?#]+$)' )
    {
        $urn = $1;
    }

    if( defined( $urn ) )
    {
        push( @{$work->{"external-ids"}->{"external-id"}},
            {
                "external-id-type" => "urn",
                "external-id-value" => $urn,
                "external-id-url" => "http://nbn-resolving.de/$urn",
                "external-id-relationship" => "SELF",
            }
        );
    }

    # ISBN
    if( $eprint->exists_and_set( "isbn" ) )
    {
        if( $eprint->exists_and_set( "type" ) && ( ( $eprint->get_value( "type" ) eq "book_section" ) || ( $eprint->get_value( "type" ) eq "encyclopedia_article" ) || ($eprint->get_value( "type" ) eq "conference_item" ) ) )
        {
            push( @{$work->{"external-ids"}->{"external-id"}},
                {
                    "external-id-type" => "isbn",
                    "external-id-value" => $eprint->get_value( "isbn" ),
                    "external-id-relationship" => "PART_OF",
                }
            );
        }
        else
        {
            push ( @{$work->{"external-ids"}->{"external-id"}},
                {
                    "external-id-type" => "isbn",
                    "external-id-value" => $eprint->get_value( "isbn" ),
                    "external-id-relationship" => "SELF",
                }
            );
        }
    }

    # Official URL
    if( $eprint->exists_and_set( "official_url" ) )
    {
        $work->{"url"} = $eprint->get_value( "official_url" );
    }

        # Contributors
    my $contributors = [];
    my %contributor_mapping = %{$repo->config( "orcid_support_advance", "contributor_map" )};
    foreach my $contributor_role ( keys %contributor_mapping )
    {
        if( $eprint->exists_and_set( $contributor_role ) )
        {
            foreach my $contributor (@{$eprint->get_value( $contributor_role )})
            {
                my $orcid_contributor = {
                    "credit-name" => $contributor->{"name"}->{"family"}.", ".$contributor->{"name"}->{"given"},
                    "contributor-attributes" => {
                        "contributor-role" => $contributor_mapping{$contributor_role}
                    },
                };

                if( defined( $contributor->{"orcid"} ) )
                {
                    my $orcid_details = {
                        "uri" => "http://orcid.org/" . $contributor->{"orcid"},
                        "path" => $contributor->{"orcid"},
                        "host" => "orcid.org",
                    };
                    $orcid_contributor->{"contributor-orcid"} = $orcid_details;
                }

                push @$contributors, $orcid_contributor;
            }
        }
    }
    $work->{"contributors"}->{"contributor"} = $contributors;

    return $work;
}

sub _curtail_abstract
{
    my( $abstract ) = @_;
    return $abstract unless ( length( $abstract ) > 5000 );
    $abstract = substr($abstract,0,4990);
    if( $abstract =~ /(.+)\b\w+$/ )
    {
        $abstract = $1;
    }
    $abstract .= " ...";
    return $abstract;
}

# a POST call is it's own function (as opposed to a PUT call which is more straightforward) because we have some follow work to do, namely save a PUT code to the eprint's creator
sub _post
{
    my( $repo, $user, $work, $users_orcid, $creators, $eprint ) = @_;

    my $result = EPrints::ORCID::AdvanceUtils::write_orcid_record( $repo, $user, "POST", "/work", $work );
    if( $result->is_success )
    {
        # Save put-code in eprints
        # XML response is empty, so we need to get it via the location in the HTTP header plus some regex
        # Example location: http://api.sandbox.orcid.org/orcid-api-web/v2.0/0000-0002-1905-9139/work/950312
        if( $result->header("Location") =~ m/^*\/$users_orcid\/work\/([0-9]*)$/ )
        {
            my $pc = $1;
            my @new_creators = ();
            foreach my $creator (@{$creators})
            {
                if( $creator->{orcid} eq $users_orcid )
                {
                    $creator->{putcode} = $pc;
                }
                push (@new_creators, $creator);
            }
            $eprint->{orcid_update} = 1;
            $eprint->set_value( "creators", \@new_creators );
            $eprint->commit;
        }
    }
    return $result;
}

sub _log_results
{
    my( $result, $results ) = @_;

    if( exists $results->{$result} )
    {
        $results->{$result} = $results->{$result} + 1;
    }
    else
    {
        $results->{$result} = 1;
    }

    return $results;
}

sub _display_results
{
    my( $repo, $results ) = @_;

    my $db = $repo->database;
    my $current_user = $repo->current_user();

    # Prepare user messages
    if( $results->{new} > 0)
    {
        $db->save_user_message( $current_user->get_value( "userid" ),
            "message",
            $repo->html_phrase(
                "ORCID::Exporter::exported_eprints",
                ( "count_successful" => $repo->xml->create_text_node( $results->{new} ) ),
                ( "count_all" => $repo->xml->create_text_node( $results->{total} ) ),
            ),
        );
    }

    if( $results->{update} > 0)
    {
        $db->save_user_message( $current_user->get_value( "userid" ),
            "message",
            $repo->html_phrase(
                "ORCID::Exporter::updated_eprints",
                ( "count_overwrite" => $repo->xml->create_text_node( $results->{update} ) ),
                ( "count_all" => $repo->xml->create_text_node( $results->{total} ) ),
            ),
        );
    }

    if( $results->{fail} > 0)
    {
        $db->save_user_message( $current_user->get_value( "userid" ),
            "error",
            $repo->html_phrase(
                "ORCID::Exporter::failed_eprints",
                ( "count_failed" => $repo->xml->create_text_node( $results->{fail} ) ),
                ( "count_all" => $repo->xml->create_text_node( $results->{total} ) ),
            ),
        );
    }
}

1;
