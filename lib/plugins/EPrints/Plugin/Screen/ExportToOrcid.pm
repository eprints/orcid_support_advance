=head1 NAME

EPrints::Plugin::Screen::ExportToOrcid

=cut

package EPrints::Plugin::Screen::ExportToOrcid;

use EPrints::Plugin::Screen;
use EPrints::ORCID::AdvanceUtils;
use JSON;
use POSIX qw(strftime);
use CGI;
use Time::Piece;

@ISA = ( 'EPrints::Plugin::Screen' );

use strict;

sub new
{
        my( $class, %params ) = @_;

        my $self = $class->SUPER::new(%params);

	$self->{actions} = [qw/ export /];

        $self->{appears} = [
		{
			place => "dataobj_view_actions",
			position => 105,
		},
		{
			place => "item_tools",
			position => 105,
		}
        ];

        return $self;
}

sub can_be_viewed{

	my( $self ) = @_;

	my $repo = $self->{repository};
        my $current_user = $self->{repository}->current_user;
        my $screenid = $self->{processor}->{screenid};

	if( $screenid eq "Items" && EPrints::Utils::is_set( $current_user->value( "orcid" ) ) ) #manage deposits screen
        {
                #has the current user given permission?
                return 1;
        }

        if( $screenid eq "Workflow::View") #user profile screen
        {
                my $userid = $self->{repository}->param( "dataobj" );
                if( defined $userid )
                {
                        #is this the current user?
                        if( $userid == $current_user->id && EPrints::Utils::is_set( $current_user->value( "orcid" ) ) )
                        {
				return 1;
                        }
                        elsif( $self->allow( "orcid_admin" ) ) #a user with permissions to do orcid admin
                        {
                                #has the subject user given permission to read their orcid.org profile?
                                my $ds = $repo->get_dataset( "user" );
                                my $user = $ds->dataobj( $userid );
				if( EPrints::Utils::is_set( $user->value( "orcid" ) ) )
                                {
                                	return 1;
				}
                        }
                }
        }

	if( $screenid eq "ExportToOrcid" ) #import screen
        {
                if( defined $self->{processor}->{orcid_user} )
                {
                        #has the subject user given permission to read their orcid.org profile?
			return EPrints::ORCID::AdvanceUtils::check_permission( $self->{processor}->{orcid_user}, "/activities/update" );
                }
        }

        return 0;
}

sub allow_export { shift->can_be_viewed }

sub action_export{
	my( $self ) = @_;

	my $repo = $self->{repository};
	
	#get the user
	my $user = $self->{processor}->{orcid_user};
	my $current_user = $repo->current_user();

	#get the eprint ids
	my $eprintids = $self->{processor}->{eprintids};

	#convert each eprint to orcid json
	my $orcid_works = [];
	my $ds = $repo->dataset( "archive" );
	my $count = 0;
	foreach my $id ( @{$eprintids} )
	{
		my $eprint = $ds->dataobj( $id );
		my $work = { work => $self->eprint_to_orcid_work( $repo, $eprint ) };
		push @$orcid_works, $work;
		$count++;
	}
	
	my $orcid_export = { "bulk" => $orcid_works };

	#write json to orcid profile activities
	my $result = EPrints::ORCID::AdvanceUtils::write_orcid_record( $repo, $user, "/works", $orcid_export );
	if( $result->is_success )
	{
		my $db = $repo->database;
	        $db->save_user_message($current_user->get_value( "userid" ),
        	        "message",
                	$repo->html_phrase("Plugin/Screen/ExportToOrcid:exported_eprints",
                        	("count"=>$repo->xml->create_text_node( $count ))
                	)
        	);

		#finished so go home
		$repo->redirect( $repo->config( 'userhome' ) );
		exit;		
	}
	else
	{
		#TODO
	}
}

sub properties_from
{
        my( $self ) = @_;

        my $repo = $self->repository;
 
        $self->SUPER::properties_from;
 
 	my $ds = $repo->dataset( "user" );

	if( !$self->{repository}->param( "orcid_userid" ) ) #only check who the user is if we are not in action import context
	{
	
		#get screenid
        	$self->{processor}->{screenid} = $self->{repository}->param( "screen" );
	
		$self->{processor}->{user} = $repo->current_user;

		my $userid = $self->{repository}->param( "dataobj" );
	      	my $user = $ds->dataobj( $userid ) if defined $userid;
	        $self->{processor}->{orcid_user} = $user || $self->{repository}->current_user;

		#if user hasn't given permission, redirect to manage permissions page
		if( !EPrints::ORCID::AdvanceUtils::check_permission( $self->{processor}->{orcid_user}, "/activities/update" ) )
        	{
                	my $db = $repo->database;
	                if( $self->{processor}->{orcid_user} eq $self->{repository}->current_user ) #redirect user to manage their permissions
        	        {
                	        $repo->redirect( $repo->config( 'userhome' )."?screen=ManageOrcid" );
	                        $db->save_user_message($self->{processor}->{orcid_user}->get_value( "userid" ),
        	                        "warning",
                	                $repo->html_phrase( "Plugin/Screen/ExportToOrcid:review_permissions" )
                        	);
	                        exit;
        	        }
                	else #we're an admin user trying to modify someone else's record
	                {
        	                $db->save_user_message($self->{repository}->current_user->get_value( "userid" ),
                	                "warning",
                        	        $repo->html_phrase("Plugin/Screen/ExportToOrcid:user_permissions",
	                                        ("user"=>$repo->xml->create_text_node("'" . EPrints::Utils::make_name_string( $self->{processor}->{orcid_user}->get_value( "name" ), 1 ) . "'"))
        	                        )
                	        );
	                        $repo->redirect( $repo->config( 'userhome' ) );
        	                exit;
	                }
        	}
	}	

	#in action export context, get user id from form, so we're definitely still working with the same user
        $self->{processor}->{orcid_user} = $ds->dataobj( $self->{repository}->param( "orcid_userid" ) ) if defined $self->{repository}->param( "orcid_userid" );

	#get selected eprints
	my @eprintids = $self->{repository}->param( "eprint" );
	$self->{processor}->{eprintids} = \@eprintids;

}

sub render
{
	my( $self ) = @_;

        my $repo = $self->{repository};
	my $xml = $repo->xml;

        my $user = $self->{processor}->{orcid_user};
	my $orcid = $user->value( "orcid" );	

	my $frag = $xml->create_document_fragment();

    $frag->appendChild( $self->render_toggle_function( $xml ) );

	#display user's name
        my $user_title = $xml->create_element( "h3", class => "orcid_subheading" );
        $user_title->appendChild( $self->html_phrase( "user_header", "user_name" => $user->render_value( "name" ) ) );
        $frag->appendChild( $user_title );

	#display user's orcid
	my $div = $xml->create_element( "div", class => "orcid_id_display" );
        $div->appendChild( $user->render_value( "orcid" ) );
	$frag->appendChild( $div );

    # add filters
    # Get URL query (important, if editor/admin wants to filter import page of another user)
    my $query = new CGI;
    $frag->appendChild( $self->render_filter_date_form( $xml, $query ) );
	#display records that might be exported
	my $dataset = $repo->dataset( "archive" );
	my $results = $dataset->search(
			filters => [
				{
					meta_fields => [qw( creators_orcid )],
					value => $orcid, match => "EX",
				}
			]);
	
	if( $results->count > 0 ) #display records to be exported
	{
		#add the intro, export buttons and display the records
		$frag->appendChild( $self->render_orcid_export( $repo, $user, $xml, $results ) );
	}

	return $frag;
}

sub render_toggle_function
{
    my( $self, $xml ) = @_;
    my $toggle_function = 'var isChecked = true;

    function toggleOrcidCheckbox() {

        var cb_putcode = document.getElementsByName("put-code");
        var cb_doi = document.getElementsByName("doi");
        var cb_eprint = document.getElementsByName("eprint");
        var arrCheckboxes = [...cb_putcode, ...cb_doi, ...cb_eprint];

        for( checkbox of arrCheckboxes ) {
            if(isChecked) {
                checkbox.checked = "";
            } else {
                checkbox.checked = "checked";
              }
         }
         isChecked = !isChecked;
    }';

    my $js_tag = $xml->create_element( "script" );
    $js_tag->appendChild( $xml->create_text_node( $toggle_function ) );
    return $js_tag;
}

sub render_filter_date_form
{
    my( $self, $xml, $query ) = @_;
    my $filter_div = $xml->create_element( "div", class => "filter_date" );
    my $filter_date_form = $xml->create_element( "form", method => "get", action => "/cgi/users/home" );
    $filter_date_form->appendChild( $xml->create_element( "input", type => "hidden", name => "screen", id => "screen", value => "ExportToOrcid") );

    # Save other params
    my $query_dataset = $query->param('dataset');
    my $query_dataobj = $query->param('dataobj');
    my $query_duplicate = $query->param('hide_duplicates');
    if( defined($query_dataset) && defined($query_dataobj) ) {
        $filter_date_form->appendChild( $xml->create_element( "input", type => "hidden", name => "dataset", value => $query_dataset) );
        $filter_date_form->appendChild( $xml->create_element( "input", type => "hidden", name => "dataobj", value => $query_dataobj) );
    }
    if( defined($query_duplicate) ){
        $filter_date_form->appendChild( $xml->create_element( "input", type => "hidden", name => "hide_duplicates", value => $query_duplicate) );
    }

    $filter_date_form->appendChild( $self->html_phrase( "show_last_modified" ) );
    my $date_picker =  $xml->create_element( "input", type => "date", name => "filter_date");
    $filter_date_form->appendChild( $date_picker );
    $filter_date_form->appendChild( $xml->create_element( "input", type => "submit", class => "ep_form_action_button filter", value => $self->html_phrase( "filter" ) ) );
    $filter_div->appendChild( $filter_date_form );
    return $filter_div;
}

#construct the export DOM components
sub render_orcid_export
{
	my( $self, $repo, $user, $xml, $records ) = @_;

	my $form = $self->render_form( "POST" );
	$form->appendChild( $repo->render_hidden_field( "orcid_userid", $user->id ) );

	$form->appendChild( $self->render_orcid_export_intro( $xml ) );
	$form->appendChild( $self->render_eprint_records( $xml, $records ) );
	$form->appendChild( $self->render_orcid_export_outro( $xml ) );

	return $form;
}

sub render_orcid_export_intro
{
	my( $self, $xml ) = @_;

	my $intro_div = $xml->create_element( "div", class => "export_intro" );
	
	#render help text
	my $help_div = $xml->create_element( "div", class => "export_intro_help" );
	$help_div->appendChild( $self->html_phrase( "export_help" ) );

	#render export button
	my $btn_div = $xml->create_element( "div", class => "export_intro_btn" );
	my $button = $btn_div->appendChild( $xml->create_element( "button",
                        type=>"submit",
                        name=>"_action_export",
			class => "ep_form_action_button",
        ) );
        $button->appendChild( $xml->create_text_node( "Export" ) );	

    # toggle switch
    my $toggle_button = $btn_div->appendChild( $xml->create_element( "button",
                    type => "button",
                    onclick => "toggleOrcidCheckbox();",
                    class => "ep_form_action_button toggle_button",
    ) );
    $toggle_button->appendChild( $xml->create_text_node( $self->html_phrase( "select" ) ) );

	$intro_div->appendChild( $help_div );
	$intro_div->appendChild( $btn_div );	

	return $intro_div;
}

sub render_eprint_records
{
	my( $self, $xml, $records ) = @_;

	my $table = $xml->create_element( "table", class => "export_orcid_records" );
	
	$records->map(sub{
		my( $session, $dataset, $eprint ) = @_;

    # modification date
    my $cgi = CGI->new();
    my $filter_date = 0;
    my $mod_date = ($eprint->get_value('lastmod'));
    $mod_date = Time::Piece->strptime( $mod_date, '%Y-%m-%d %H:%M:%S' );
    if( defined $cgi->param('filter_date'))
    {
        $filter_date = $cgi->param('filter_date');
        $filter_date = Time::Piece->strptime( $filter_date, '%Y-%m-%d' );
    }
		#show the eprint citation
		my $tr = "";
		my $td_citation = $session->make_element( "td", class => "export_orcid_citation" );
		$td_citation->appendChild($eprint->render_citation_link );
		if( $mod_date < $filter_date )
        {
            $tr = $session->make_element( "tr", class => "filtered" );
            $td_citation->appendChild( $xml->create_text_node( "Moddate: $mod_date" ) );
            $td_citation->appendChild( $xml->create_element("br"));
            $td_citation->appendChild( $xml->create_text_node( "Filterdate: $filter_date" ) );
            $td_citation->appendChild( $xml->create_element("br"));
            $tr->appendChild( $td_citation );
        }
        else
        {
            $tr = $session->make_element( "tr" );
            $tr->appendChild( $td_citation );
            #show checkbox for this record
            my $td_check = $session->make_element( "td", class => "export_orcid_check" );
            my $checkbox = $session->make_element( "input",
                type => "checkbox",
                name => "eprint",
                value => $eprint->id,
            );
            $checkbox->setAttribute( "checked", "yes" );
            $td_check->appendChild( $checkbox );
            $tr->appendChild( $td_check );
        }
		$table->appendChild( $tr );
	});

	return $table;
}

sub render_orcid_export_outro
{
	my( $self, $xml ) = @_;

	my $btn_div = $xml->create_element( "div", class => "export_outro_btn" );
        my $button = $btn_div->appendChild( $xml->create_element( "button",
                        type => "submit",
                        name => "_action_export",
			class => "ep_form_action_button",
        ) );
        $button->appendChild( $xml->create_text_node( "Export" ) );

    # toggle switch
    my $toggle_button = $btn_div->appendChild( $xml->create_element( "button",
                    type => "button",
                    onclick => "toggleOrcidCheckbox();",
                    class => "ep_form_action_button toggle_button",
    ) );
    $toggle_button->appendChild( $xml->create_text_node( $self->html_phrase( "select" ) ) );

	return $btn_div;
}

sub eprint_to_orcid_work
{
	my( $self, $repo, $eprint ) = @_;

	my $work = { "title" => { "title" => { "value" => $eprint->get_value( "title" )	} } };

	$work->{"type"} = &{$repo->config( "plugins" )->{"Screen::ExportToOrcid"}->{"work_type"}}($eprint);

	#set journal title, if relevant
	if( $eprint->exists_and_set( "type" ) && $eprint->get_value( "type" ) eq "article" && $eprint->exists_and_set( "publication" ) )
	{
		$work->{"journal-title"} = $eprint->get_value( "publication" );
	}

	#add abstract, if relevant
	$work->{"short-description"} = curtail_abstract( $eprint->get_value( "abstract" ) ) if $eprint->exists_and_set( "abstract" );

	#*** Citations not support in APIv2???***
	#add citation
	#my $bibtex_plugin = EPrints::Plugin::Export::BibTeX->new();
	#$bibtex_plugin->{"session"} = $repo;
	#$work->{"citation"} = {
	#	"citation-type" => "bibtex",
	#	"citation-value" => $bibtex_plugin->output_dataobj( $eprint ),
	#};

	#publication date
	if( $eprint->exists_and_set( "date" ) )
	{
		$work->{"publication-date"} = {
			"year" => 0 + substr( $eprint->get_value( "date" ),0,4),
			"month" => length( $eprint->get_value( "date" )) >=7 ? 0 + substr( $eprint->get_value( "date" ),5,2) : undef,
			"day" => length( $eprint->get_value( "date" )) >=9 ? 0 + substr( $eprint->get_value( "date" ),8,2) : undef,
		}
	}

	#EPrint identifiers
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


	#DOIs
	my $doi = undef;
	if( $eprint->exists_and_set( "doi" ) && $eprint->get_value( "doi" ) =~ m#(doi:)?[doixrg.]*(10\..*)$# )
	{
		$doi = $2;
	}
	if( !defined( $doi ) && $eprint->exists_and_set( "id_number" ) && $eprint->get_value( "id_number" ) =~ m#(doi:)?[doixrg./]*(10\..*)$# )
	{
		$doi = $2;
	}	
	
	if( defined( $doi ) )
	{
		push ( @{$work->{"external-ids"}->{"external-id"}}, {
				"external-id-type" => "doi",
				"external-id-value" => $doi,	
				"external-id-relationship" => "SELF",
			});
	}
	
	#Official URL
	if( $eprint->exists_and_set( "official_url" ) )
	{
		$work->{"url"} = $eprint->get_value( "official_url" ); 
	}

	#Contributors
	my $contributors = [];
	my %contributor_mapping = %{$repo->config( "orcid_support_advance", "contributor_map" )};
	foreach my $contributor_role ( keys %contributor_mapping )
	{

		if( $eprint->exists_and_set( $contributor_role ))
		{
			foreach my $contributor (@{$eprint->get_value( $contributor_role )})
			{
								
				my $orcid_contributor = { 
					"credit-name" => $contributor->{"name"}->{"family"}.", ".$contributor->{"name"}->{"given"},
					"contributor-attributes" => {
						"contributor-role" => $contributor_mapping{$contributor_role}
					},
				};

				if( defined( $contributor->{"orcid"} ))
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


sub curtail_abstract
{
        my ( $abstract ) = @_;
        return $abstract unless ( length( $abstract ) > 5000 );
        $abstract = substr($abstract,0,4990);
        if ( $abstract =~ /(.+)\b\w+$/ )
        {
                $abstract = $1;
        }
        $abstract .= " ...";
        return $abstract;
}
