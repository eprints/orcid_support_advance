=head1 NAME

EPrints::Plugin::Screen::ImportFromOrcid

=cut

package EPrints::Plugin::Screen::ImportFromOrcid;

use EPrints::Plugin::Screen;
use EPrints::ORCID::Utils;
use EPrints::ORCID::AdvanceUtils;
use JSON;
use POSIX qw(strftime);
use CGI;
use Time::Local;
use Data::Dumper;


@ISA = ( 'EPrints::Plugin::Screen' );

use strict;

sub new
{
        my( $class, %params ) = @_;

        my $self = $class->SUPER::new(%params);

	$self->{actions} = [qw/ import /];

        $self->{appears} = [
		{
			place => "dataobj_view_actions",
			position => 100,
		},
		{
			place => "item_tools",
			position => 100,
		}
        ];

        return $self;
}

sub can_be_viewed
{
	my( $self ) = @_;

	my $repo = $self->{repository};
	my $current_user = $self->{repository}->current_user;
	my $screenid = $self->{processor}->{screenid};

	if( $screenid eq "Items" && EPrints::Utils::is_set( $current_user->value( "orcid" ) ) ) #manage deposits screen
	{
		#has the current user given permission?
		return 1;
	}

     my $dataset = $self->{repository}->param( "dataset" );
     if( $screenid eq "Workflow::View" && $dataset eq 'user') #user profile screen
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
				if( defined $user && EPrints::Utils::is_set( $user->value( "orcid" ) ) )
				{
					return 1;
				}
			}
		}
	}

	if( $screenid eq "ImportFromOrcid" ) #import screen
	{
		if( defined $self->{processor}->{orcid_user} )
		{
			#has the subject user given permission to read their orcid.org profile?
			return EPrints::ORCID::AdvanceUtils::check_permission( $self->{processor}->{orcid_user}, "/read-limited" );
		}
	}

	return 0;
}

sub allow_import{ shift->can_be_viewed }

sub action_import
{
	my( $self ) = @_;

	my $repo = $self->{repository};

	$self->{processor}->{action} = "import";

	my $dataset = $repo->get_dataset( "inbox" );

	#get the user
	my $user = $self->{processor}->{orcid_user};
	my $current_user = $repo->current_user();

	my $put_codes =	$self->{processor}->{put_codes};
	my $works = $self->{processor}->{works};
	my $count = 0;

	foreach my $work ( @{$works} )
	{
		if( grep( /^$work->{'put-code'}$/, @{$put_codes} ) )
		{
			my $eprint = $self->import_via_orcid( $repo, $user, $work );
			if( $eprint )
			{
				$count++;
			}
		}
	}

	my $db = $repo->database;
	$db->save_user_message($current_user->get_value( "userid" ),
                "message",
                $repo->html_phrase("Plugin/Screen/ImportFromOrcid:imported_works",
                        ("count"=>$repo->xml->create_text_node( $count ))
                )
        );

	#finished so go home
	$repo->redirect( $repo->config( 'userhome' ) );
	exit;


	#get the DOIs
        #my $dois = $self->{processor}->{dois};

	#get DOI import plugin
	#my $plugin = $repo->plugin(
        #	"Import::DOI",
        #        session => $repo,
	#        dataset => $dataset,
        #        processor => $self->{processor},
        #);

	#if( !defined $plugin || $plugin->broken )
	#{
        #	$self->{processor}->add_message( "error", $self->{session}->html_phrase( "general:bad_param" ) );
	#        return;
        #}

	#my $tmpfile = File::Temp->new;
        #binmode($tmpfile, ":utf8");
        #print $tmpfile join( "\n", @{$dois} );
        #seek($tmpfile, 0, 0);

	#my $list = eval {
        #	$plugin->input_fh(
        #                dataset=>$dataset,
        #                fh=>$tmpfile,
        #                user=>$user,
        #                encoding=>"UTF-8",
        #        );
        #};
}

sub properties_from
{
        my( $self ) = @_;

        my $repo = $self->repository;
        $self->SUPER::properties_from;

	my $ds = $repo->dataset( "user" );

	if( !$self->{repository}->param( "orcid_userid" ) ) #only check who the user is if we are not in an action import context
	{
		#get screenid
		$self->{processor}->{screenid} = $self->{repository}->param( "screen" );

	        #get appropriate user
	        $self->{processor}->{user} = $repo->current_user;

		my $userid = $self->{repository}->param( "dataobj" );
		my $user = $ds->dataobj( $userid ) if defined $userid;
		$self->{processor}->{orcid_user} = $user || $self->{repository}->current_user;

		#if user hasn't given permission, redirect to manage permissions page
		if( !EPrints::ORCID::AdvanceUtils::check_permission( $self->{processor}->{orcid_user}, "/read-limited" ) )
		{
			my $db = $repo->database;
			if( $self->{processor}->{orcid_user} eq $self->{repository}->current_user ) #redirect user to manage their permissions
			{
				$repo->redirect( $repo->config( 'userhome' )."?screen=ManageOrcid" );
				$db->save_user_message($self->{processor}->{orcid_user}->get_value( "userid" ),
        	        		"warning",
			                $repo->html_phrase( "Plugin/Screen/ImportFromOrcid:review_permissions" )
		        	);
				exit;
			}
			else #we're an admin user trying to modify someone else's record
			{
				$db->save_user_message($self->{repository}->current_user->get_value( "userid" ),
                			"warning",
		        		$repo->html_phrase("Plugin/Screen/ImportFromOrcid:user_permissions",
	                        		("user"=>$repo->xml->create_text_node("'" . EPrints::Utils::make_name_string( $self->{processor}->{orcid_user}->get_value( "name" ), 1 ) . "'"))
        	        		)
			        );
				$repo->redirect( $repo->config( 'userhome' ) );
				exit;
			}
		}
	}

	#in action import context, get user id from form, so we're definitely still working with the same user
	$self->{processor}->{orcid_user} = $ds->dataobj( $self->{repository}->param( "orcid_userid" ) ) if defined $self->{repository}->param( "orcid_userid" );

	#get selected works
        my @put_codes = $self->{repository}->param( "put-code" );
	$self->{processor}->{put_codes} = \@put_codes;

    my $hide_duplicates = 1;
    my $query = new CGI;
    if( defined($query->param('hide_duplicates')) )
    {
        $hide_duplicates = $query->param('hide_duplicates');
    }

    #get works
    $self->{processor}->{works} = EPrints::ORCID::AdvanceUtils::read_orcid_works( $repo, $self->{processor}->{orcid_user}, $hide_duplicates );
}

sub render
{
    my( $self ) = @_;

    my $repo = $self->{repository};
    my $xml = $repo->xml;

    my $user = $self->{processor}->{orcid_user};

    my $frag = $repo->xml->create_document_fragment();

    $frag->appendChild( $self->render_toggle_function( $xml ) );

    # display user's name
    my $user_title = $repo->xml->create_element( "h2", class => "orcid_subheading" );
    $user_title->appendChild( $self->html_phrase( "user_header", "user_name" => $user->render_value( "name" ) ) );
    $frag->appendChild( $user_title );

    # display user's orcid
    my $div = $repo->xml->create_element( "div", class => "orcid_id_display" );
    $div->appendChild( $self->html_phrase( "intro", "orcid" => $user->render_value( "orcid" ) ) );
    $frag->appendChild( $div );

    # Add filters
    # Get URL query (important, if editor/admin wants to filter import page of another user)
    my $query = new CGI;
    $frag->appendChild( $self->render_filter_date_form( $xml, $query ) );
    $frag->appendChild( $self->render_filter_duplicate_form( $xml, $query ) );

	#display records that might be imported
	#my $response = EPrints::ORCID::AdvanceUtils::read_orcid_record( $repo, $user, "/works" );
	my $works = $self->{processor}->{works};
	if( scalar( $works > 0 ) )
	{
		$frag->appendChild( $self->render_orcid_import( $repo, $user, $xml, $works ) );
	}
	else
	{
		#we've been unable to get a response from orcid for some reason
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

    my $repo = $self->{repository};

    my $filter_div = $xml->create_element( "div", class => "filter_date" );
    my $filter_date_form = $xml->create_element( "form", method => "get", action => "/cgi/users/home" );
    $filter_date_form->appendChild( $xml->create_element( "input", type => "hidden", name => "screen", id => "screen", value => "ImportFromOrcid") );

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
 
    my $date_type = $repo->config( "orcid_support_advance", "filter_date" ) || "last-modified-date";
    $filter_date_form->appendChild( $self->html_phrase( "show_$date_type" ) );
    my $date_picker = $xml->create_element( "input", type => "date", name => "filter_date", "aria-label" => "Filter Date", value => $query->param('filter_date') );

    $filter_date_form->appendChild( $date_picker );
    $filter_date_form->appendChild( $xml->create_element( "input", type => "submit", class => "ep_form_action_button filter", value => $self->phrase( "filter" ) ) );
    $filter_div->appendChild( $filter_date_form );
    return $filter_div;
}

sub render_filter_duplicate_form
{
    my( $self, $xml, $query ) = @_;
    my $duplicate_div = $xml->create_element( "div", class => "filter_duplicate" );
    my $filter_duplicate_form = $xml->create_element( "form", method => "get", action => "/cgi/users/home" );
    $filter_duplicate_form->appendChild( $xml->create_element( "input", type => "hidden", name => "screen", id => "screen", value => "ImportFromOrcid") );

    # Save other params
    my $query_dataset = $query->param('dataset');
    my $query_dataobj = $query->param('dataobj');
    my $query_date = $query->param('filter_date');
    my $query_duplicate = $query->param('hide_duplicates');
    if( defined($query_dataset) && defined($query_dataobj) ) {
        $filter_duplicate_form->appendChild( $xml->create_element( "input", type => "hidden", name => "dataset", value => $query_dataset) );
        $filter_duplicate_form->appendChild( $xml->create_element( "input", type => "hidden", name => "dataobj", value => $query_dataobj) );
    }
    if( defined($query_date) ){
        $filter_duplicate_form->appendChild( $xml->create_element( "input", type => "hidden", name => "filter_date", value => $query_date) );
    }

    if( defined($query_duplicate) )
    {
        if( $query_duplicate == 1 )
        {
            $filter_duplicate_form->appendChild( $xml->create_element( "input", type => "hidden", name => "hide_duplicates", value => 0) );
        } else {
            $filter_duplicate_form->appendChild( $xml->create_element( "input", type => "hidden", name => "hide_duplicates", value => 1) );
        }
    } else {
        $filter_duplicate_form->appendChild( $xml->create_element( "input", type => "hidden", name => "hide_duplicates", value => 0) );
    }


    $filter_duplicate_form->appendChild( $self->html_phrase( "duplicates" ) );
    $filter_duplicate_form->appendChild( $xml->create_element( "input", type => "submit", class => "ep_form_action_button filter", value => $self->phrase( "show_hide_duplicates" )));
    $duplicate_div->appendChild( $filter_duplicate_form );
    return $duplicate_div;
}

#construct the import DOM components
sub render_orcid_import
{
	my( $self, $repo, $user, $xml, $works ) = @_;
	my $form = $self->render_form( "POST" );
        $form->appendChild( $repo->render_hidden_field( "orcid_userid", $user->id ) );

	$form->appendChild( $self->render_orcid_import_intro( $xml ) );
	$form->appendChild( $self->render_orcid_records( $repo, $works ) );
	$form->appendChild( $self->render_orcid_import_outro( $xml ) );

	return $form;
}

sub render_orcid_import_intro
{
        my( $self, $xml ) = @_;
        my $intro_div = $xml->create_element( "div", class => "import_intro" );

        #render import button
        my $btn_div = $xml->create_element( "div", class => "import_intro_btn" );
        my $button = $btn_div->appendChild( $xml->create_element( "button",
                        type => "submit",
                        name => "_action_import",
                        class => "ep_form_action_button",
        ) );
        $button->appendChild( $xml->create_text_node( "Import" ) );

        # toggle switch
        my $toggle_button = $btn_div->appendChild( $xml->create_element( "button",
                        type => "button",
                        onclick => "toggleOrcidCheckbox();",
                        class => "ep_form_action_button toggle_button",
        ) );
#        $toggle_button->appendChild( $xml->create_text_node( $self->html_phrase( "select" ) ) );
        $toggle_button->appendChild( $self->html_phrase( "select" ) );

        $intro_div->appendChild( $btn_div );

        return $intro_div;
}

sub render_orcid_import_outro
{
	my( $self, $xml ) = @_;

	my $btn_div = $xml->create_element( "div", class => "import_outro_button" );

	my $button = $btn_div->appendChild( $xml->create_element( "button",
		type => "submit",
		name => "_action_import",
		class => "ep_form_action_button",
	) );
	$button->appendChild( $xml->create_text_node( "Import" ) );

    # toggle switch
    my $toggle_button = $btn_div->appendChild( $xml->create_element( "button",
                    type => "button",
                    onclick => "toggleOrcidCheckbox();",
                    class => "ep_form_action_button toggle_button",
    ) );
    $toggle_button->appendChild( $self->html_phrase( "select" ) );

	return $btn_div;
}

sub render_orcid_records
{
	my( $self, $repo, $works ) = @_;

	my $xml = $repo->xml;
	my $import_count = 0;
	my $fieldset = $xml->create_element( "fieldset", class => "orcid_imports" );

    my $legend = $xml->create_element( "legend", id=>"orcid_import_legend", class=>"ep_field_legend" );
    $legend->appendChild( $self->html_phrase( "import_help" ) );
    $fieldset->appendChild( $legend );

    foreach my $work ( @{$works} )
	{
		$fieldset->appendChild( $self->render_orcid_item( $repo, $xml, $work ) );
        $import_count++;
	}
    if( $import_count == 0 ) {
        $fieldset->appendChild( $self->html_phrase( "no_items" ) );
    }
	return $fieldset;
}

sub render_orcid_item
{
	my( $self, $repo, $xml, $work ) = @_;
	my $li = $xml->create_element( "div", class => "orcid_item" );

	my $summary = $xml->create_element( "div", class => "orcid_summary" );
	#render title
	my $title = $work->{'title'}->{'title'}->{'value'};
	$summary->appendChild( $self->render_orcid_text( $xml, $title, "title" ) );
    if( defined $work->{'title'}->{'subtitle'} )
    {
        $summary->appendChild( $self->render_orcid_text( $xml, $work->{'title'}->{'subtitle'}->{'value'}, "subtitle" ) );
    }

	#get date + type
	my $date = "";
        $date .= $work->{'publication-date'}->{'day'}->{'value'} if $work->{'publication-date'}->{'day'}->{'value'};
        $date .= "/".$work->{'publication-date'}->{'month'}->{'value'} if $work->{'publication-date'}->{'month'}->{'value'};
        $date .= "/".$work->{'publication-date'}->{'year'}->{'value'} if $work->{'publication-date'}->{'year'}->{'value'};

	#type
	my $type = $work->{'type'};

	#date|type string
	my $date_type = "";
	$date_type .= $date if $date ne "";
	$date_type .= " | " if $date ne "" && defined $type;
	$date_type .= $type if defined $type;
	$summary->appendChild( $self->render_orcid_text( $xml, $date_type, "date-type" ) );

	#ext identifiers
	my $ext_ids = $work->{'external-ids'}->{'external-id'};
	my $id_ul = $xml->create_element( "ul", class => "external_identifiers" );
        foreach my $ext_id ( @$ext_ids )
        {
            my $id_type = $ext_id->{'external-id-type'};
            my $id = $ext_id->{'external-id-value'};
            my $id_url = $ext_id->{'external-id-url'}->{'value'};
            $id_ul->appendChild( $self->render_ext_id( $xml, $id_type, $id, $id_url ) );
	}
	$summary->appendChild( $id_ul );

	#source
	my $source = $work->{'source'}->{'source-name'}->{'value'};
	$summary->appendChild( $self->render_orcid_text( $xml, "Source: $source", "source" ) );

	#import
	my $import = $xml->create_element( "div", class => "orcid_import" );
	my $existing_id = $work->{'$existing_id'};

    #modification date (divided by 1000 because of different time handling seconds/milliseconds by epoch/unix)
    my $cgi = CGI->new();
    my $filter_date = 0;
    my $work_date = $self->get_work_date( $repo, $work );
    if( defined $cgi->param('filter_date'))
    {
        $filter_date = $cgi->param('filter_date');
        my( $year, $month, $day ) = $filter_date =~ /^(\d{4})-(\d{2})-(\d{2})$/;
        $filter_date = timegm( 0, 0, 0, $day, $month-1, $year-1900 );
    }
	if( $existing_id )
	{
		$import->setAttribute( "class", "orcid_import warning" );
		$import->appendChild( $self->render_duplicate_record( $repo, $xml, $existing_id ) );
        $li->setAttribute( "class", "orcid_item duplicate" );
	}
    elsif( $work_date < $filter_date )
    {
		$import->setAttribute( "class", "orcid_import warning" );
		$import->appendChild( $self->render_filtered_record( $repo, $xml, $work_date, $filter_date ) );
        $li->setAttribute( "class", "orcid_item filtered" );
    }
	else
	{
		$import->appendChild( $self->render_import_work( $repo, $xml, $work ) );
	}

	$li->appendChild( $summary );
	$li->appendChild( $import );

	return $li;
}

sub render_orcid_text
{
	my( $self, $xml, $data, $class ) = @_;

	my $span = $xml->create_element( "div", class => $class );
	$span->appendChild( $xml->create_text_node( $data ) );
	return $span;
}

sub render_ext_id
{
	my( $self, $xml, $identifier, $value, $url ) = @_;

	my $id_li = $xml->create_element( "li" );
	my $label = $xml->create_text_node( $identifier . ": " );
    $id_li->appendChild( $label );
    if( defined $url )
    {
        my $link = $xml->create_element( "a", href=>$url, target=>"_blank" );
        $link->appendChild( $xml->create_text_node( $value ) );
        $id_li->appendChild( $link );
    }
    else
    {
        $id_li->appendChild( $xml->create_text_node( $value ) );
    }
	return $id_li;
}

sub render_duplicate_record
{
	my( $self, $repo, $xml, $existing_id ) = @_;
	my $div = $xml->create_element( "div", class => "duplicate_record" );

	#get duplicate record
	my $ds = $repo->dataset( "eprint" );
	my $eprint = $ds->dataobj( @{$existing_id}[0] );
	$div->appendChild( $self->html_phrase(
		"orcid_duplicate_record",
		title => $eprint->render_value( "title" )
	) );
	return $div;
}

sub render_filtered_record
{
	my( $self, $repo, $xml, $work_date, $filter_date ) = @_;
	my $div = $xml->create_element( "div", class => "filtered_record_info" );
 
    my $date_format = $repo->config( "orcid_support_advance", "filter_format" ) || "%d/%m/%Y";

    # work date
    my $date_type = $repo->config( "orcid_support_advance", "filter_date" ) || "last-modified-date";
    $work_date = strftime $date_format, gmtime( $work_date );
    $div->appendChild( $self->html_phrase( $date_type ) );
    $div->appendChild( $xml->create_text_node( $work_date ) );

    $div->appendChild( $xml->create_element( "br" ) );
 
    # filter date
    $filter_date = strftime $date_format, gmtime( $filter_date );
    $div->appendChild( $xml->create_text_node( "Filter date: $filter_date" ) );
    $div->appendChild( $xml->create_element( "br" ) );
	return $div;
}


#checkbox for importing work via JSON return from orcid.org
sub render_import_work
{
	my( $self, $repo, $xml, $work ) = @_;

	my $div = $xml->create_element( "div", class => "orcid_import_work" );

	my $label = $self->html_phrase( "orcid_import_work" );

	my $checkbox = $repo->make_element( "input",
                        type => "checkbox",
                        name => "put-code",
                        "aria-label" => $work->{'title'}->{'title'}->{'value'},
        );

	$checkbox->setAttribute( "checked", "yes" );
        $checkbox->setAttribute( "value", $work->{'put-code'} );

	$div->appendChild( $checkbox );
        $div->appendChild( $label );

	return $div;
}

#chekcbox for importing work via DOI
sub render_import_doi
{
	my( $self, $repo, $xml, $work_summary ) = @_;

	my $div = $xml->create_element( "div", class => "orcid_import_doi" );

	my $label = $self->html_phrase( "orcid_import_via_doi" );
	my $checkbox = $repo->make_element( "input",
                        type => "checkbox",
                        name => "doi",
        );

	#get the DOI
	my $doi;
	my $ext_ids = $work_summary->{'external-ids'}->{'external-id'};
        foreach my $ext_id ( @$ext_ids )
        {
                if( $ext_id->{'external-id-type'} eq "doi" )
		{
			$doi = $ext_id->{'external-id-value'};
			last;
		}
        }

	if( defined $doi )
	{
		#reformat doi for import plugin
		$doi =~ s/^(http(s)?:\/\/(dx\.)?doi\.org\/)//i;

		$checkbox->setAttribute( "checked", "yes" );
		$checkbox->setAttribute( "value", $doi );
	}
	else
	{
		$checkbox->setAttribute( "disabled" );
	}

	$div->appendChild( $checkbox );
        $div->appendChild( $label );

	return $div;
}


sub import_via_orcid
{
	my( $self, $repo, $user, $work ) = @_;

	#If we have a work:citation and an import plugin that can
	#process it, we should use that to "prime" the eprint.
	#Parsed ORCID data will then take precedent

	my $epdata = {};

	if(EPrints::Utils::is_set($work->{citation})){

		my $tmpfile = File::Temp->new;
		binmode($tmpfile, ":utf8");
		print $tmpfile $work->{citation}->{"citation-value"};
		seek($tmpfile, 0, 0);

		if(EPrints::Utils::is_set($work->{citation}->{"citation-type"})){
		    my $pluginid = $repo->config( "orcid_support_advance", "import_citation_type_map" )->{$work->{citation}->{"citation-type"}};
	 	    my $plugin = $repo->plugin( "Import::".$pluginid );

		    unless( !defined $plugin )
		    {
			    my $parser = BibTeX::Parser->new( $tmpfile );
			    while(my $entry = $parser->next)
			    {
				if( !$entry->parse_ok )
				{
				    $plugin->warning( "Error parsing: " . $entry->error );
				    next;
				}
				$epdata = $plugin->convert_input( $entry );
				next unless defined $epdata;
			    }
  		    }
		}
	}
	$epdata->{eprint_status} = $repo->config( "orcid_support_advance", "import_destination") || "inbox";
	$epdata->{userid} = $user->get_value( "userid" );

	#create the eprint object
	my $eprint = $repo->dataset( 'eprint' )->create_dataobj($epdata);

	if( defined( $work->{"type"} ) )
	{
		$eprint->set_value( "type", &{$repo->config( "orcid_support_advance", "work_type_to_eprint" )}( $work->{"type"} ) );
	}

	if( defined( $work->{"title"}->{"title"}->{"value"} ) )
	{
        if( defined( $work->{"title"}->{"subtitle"}->{"value"} ) )
        {
            my $title = $work->{"title"}->{"title"}->{"value"};
            my $subtitle = $work->{"title"}->{"subtitle"}->{"value"};
            my $complete_title = "";
            if( $title =~ m/\W$/ )
            {
                $complete_title = $complete_title = $title . " " . $subtitle;
            }
            else
            {
                $complete_title = $title . ": " . $subtitle;
            }
            $eprint->set_value( "title", $complete_title );
        }
        else
        {
    		$eprint->set_value( "title", $work->{"title"}->{"title"}->{"value"} );
        }
	}

	if( defined( $work->{"journal-title"}->{"value"} ) )
	{
		$eprint->set_value( "publication" , $work->{"journal-title"}->{"value"} );
	}

	if( defined( $work->{"short-description"} ) )
	{
		$eprint->set_value( "abstract", $work->{"short-description"} );
	}

 	#publication date
 	if( defined($work->{"publication-date"}) )
 	{
        my $year = $work->{"publication-date"}->{"year"}->{'value'};
        my $month = $work->{"publication-date"}->{"month"}->{'value'};
        my $day = $work->{"publication-date"}->{"day"}->{'value'};
        my $date = $year . "-" . $month . "-" . $day;
	}

	if( defined( $work->{"url"} ) )
	{
		$eprint->set_value( "official_url", $work->{"url"}->{"value"} );
	}

	if( defined( $work->{"external-ids"}->{"external-id"} ) )
	{
		foreach my $identifier (@{$work->{"external-ids"}->{"external-id"}} )
		{
			if( $identifier->{"external-id-type"} eq "doi" )
			{
				if( $repo->dataset( 'eprint' )->has_field( "doi" ) )
				{
					$eprint->set_value( "doi", $identifier->{"external-id-value"} );
				}
				else
				{
					$eprint->set_value( "id_number", "doi".$identifier->{"external-id-value"} );
				}
			}
		        elsif ( $identifier->{"external-id-type"} eq "urn" )
            		{
				if( $repo->dataset( 'eprint' )->has_field( "urn" ) )
				{
					$eprint->set_value( "urn", $identifier->{"external-id-value"} );
				}
				else
				{
					$eprint->set_value( "id_number", $identifier->{"external-id-value"} );
				}
            		}
            		elsif ( $identifier->{"external-id-type"} eq "issn" )
            		{
				$eprint->set_value( "issn", $identifier->{"external-id-value"} );
            		}
            		elsif ( $identifier->{"external-id-type"} eq "isbn" )
            		{
				$eprint->set_value( "isbn", $identifier->{"external-id-value"} );
            		}
		}
	}

	#contributors
	my %eprint_contribs;
    foreach my $role ( @{$repo->config( "orcid", "eprint_fields" )} )
    {
        $eprint_contribs{$role} = [];
    }
	if( defined( $work->{"contributors"} )  && scalar @{$work->{"contributors"}->{"contributor"}} )
	{
		foreach my $contributor (@{$work->{"contributors"}->{"contributor"}} )
		{
            		my ($username,$putcode,$orcid) = undef;

            		my $users_orcid = $user->value( "orcid" );
			my $c_user; # a user object derived from creator object, additional to the logged in one
			if( defined( $contributor->{"contributor-orcid"} ) )
			{
				#search for user with orcid and add username to eprint contributor if found
				$orcid = $contributor->{"contributor-orcid"}->{"path"} if $contributor->{"contributor-orcid"}->{"path"} ne "null";
				$c_user = EPrints::ORCID::Utils::user_with_orcid( $repo, $orcid );

                		# Save putcode if this contributor is the importing user
                		if( $users_orcid eq $orcid )
                		{
                    			my @work_putcodes = ( $work->{"put-code"} );
                    			foreach my $work_putcode (@work_putcodes)
                    			{
                        			$putcode = $work_putcode;
                    			}
                		}

			}

			#What kind of contributor is this?  Pull match from config
			my $contrib_role = $contributor->{"contributor-attributes"}->{"contributor-role"};
			my %contrib_config = %{$repo->config( "orcid_support_advance", "contributor_map" )};
			foreach my $contrib_type ( keys %contrib_config )
			{
				if( $contrib_config{$contrib_type} eq $contrib_role )
				{
					$contrib_role = $contrib_type;
				}
			}
			#construct a hash of appropriate info
			my( $honourific, $given, $family ) = EPrints::ORCID::AdvanceUtils::get_name( $contributor->{"credit-name"}->{"value"} );
			my $contributor = {
				name => {
					honourific => $honourific,
					given => $given,
					family => $family,
				},
			};
            		#putcode only or
			$contributor->{"putcode"} = $putcode if defined $putcode;
			#Add orcid if we have one
			$contributor->{orcid} = $orcid if defined $orcid;
			#Add user email if we have linked a user
			$contributor->{"id"} = $c_user->get_value( "email" ) if defined $c_user;

			#add user to appropriate field
			for my $key (keys %eprint_contribs)
            {
                if( $contrib_role eq $key ){
                    push @{$eprint_contribs{$key}}, $contributor;
                }
            }
		}
	}

    # If there are no contributors whatsoever...
    my $no_contribs = 1;
    for my $key (keys %eprint_contribs)
    {
        if( @{$eprint_contribs{$key}} || $eprint->is_set($key) )
        {
            $no_contribs = 0;
            last;
        }
    }
    # ...assume the user is a creator
    if( $no_contribs )
    {
        my $users_name = $user->get_value("name");
        my $putcode = undef;
        my @work_putcodes = ( $work->{"put-code"} );
        foreach my $work_putcode (@work_putcodes)
        {
            $putcode = $work_putcode;
        }
		my $contributor = {
			name => {
				given => $users_name->{given},
				family => $users_name->{family},
			},
       		id => $user->get_value( "email" ),
			orcid => $user->value( "orcid" ),
			putcode => $putcode,
		};
        push @{$eprint_contribs{creators}}, $contributor;
    }

    # Set the contributors (overwrites what might have been gleaned from citation)
    for my $key (keys %eprint_contribs)
    {
        $eprint->set_value( $key, $eprint_contribs{$key} ) if EPrints::Utils::is_set(@{$eprint_contribs{$key}});
    }

	#save the record
	$eprint->commit;
#	print STDERR "creators in eprint: ".Dumper($eprint->value( "creators"))."\n";
	return $eprint;
}

# return a date for the filtering process - depending on the type of date we're after we'll need to retrieve it in different ways
sub get_work_date
{
    my( $self, $repo, $work ) = @_;

    my $date_type = $repo->config( "orcid_support_advance", "filter_date" ) || "last-modified-date";
    if( $date_type eq "last-modified-date" || $date_type eq "created-date" )
    {
        return $work->{$date_type}->{'value'} / 1000;
    }
    elsif( $date_type eq "publication-date" )
    {       
        my $year = $work->{$date_type}->{year}->{value} if( defined $work->{$date_type}->{year}->{value} );
        my $month = $work->{$date_type}->{month}->{value} if( defined $work->{$date_type}->{month}->{value} );
        my $day = $work->{$date_type}->{day}->{value} if( defined $work->{$date_type}->{day}->{value} );
        if( defined $year && defined $month && defined $day )
        {
            return timegm( 0, 0, 0, $day, $month-1, $year-1900 );
        }
    }

    # nothing we can really work with... :(
    return undef;
}
