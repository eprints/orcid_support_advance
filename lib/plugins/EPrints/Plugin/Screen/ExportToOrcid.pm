=head1 NAME

EPrints::Plugin::Screen::ExportToOrcid

=cut

package EPrints::Plugin::Screen::ExportToOrcid;

use EPrints::Plugin::Screen;
use EPrints::ORCID::AdvanceUtils;
use EPrints::ORCID::Exporter;
use JSON;
use POSIX qw(strftime);
use CGI;
use Time::Piece;
use XML::LibXML;
use XML::LibXML::XPathContext;

@ISA = ( 'EPrints::Plugin::Screen' );

use strict;

sub new
{
        my( $class, %params ) = @_;

        my $self = $class->SUPER::new(%params);

	$self->{actions} = [qw/ export delete /];

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

	# get the user
	my $user = $self->{processor}->{orcid_user};
	my $current_user = $repo->current_user();

	# get the eprint ids
	my $eprintids = $self->{processor}->{eprintids};

    # get the eprints and then send them to the exporter
	my $ds = $repo->dataset( "archive" );
    my @eprints;
	foreach my $id ( @{$eprintids} )
	{
        push @eprints, $ds->dataobj( $id );
    }
 
    EPrints::ORCID::Exporter::export_user_eprints( $repo, $user, @eprints );   

	# finished so go home
	$repo->redirect( $repo->config( 'userhome' ) );
	exit;

}

sub allow_delete{ shift->can_be_viewed }

sub action_delete{
    my( $self ) = @_;

    my $repo = $self->{repository};

    #get the user
    my $user = $self->{processor}->{orcid_user};
    my $current_user = $repo->current_user();

    #get the eprint ids
    my $eprintids = $self->{processor}->{eprintids};

    #initialize some variables
    my $ds = $repo->dataset( "archive" );
    my $db = $repo->database;
    my $count_all = 0;
    my $count_successful = 0;
    my $count_failed = 0;

    foreach my $id ( @{$eprintids} )
    {
        $count_all++;
        my $eprint = $ds->dataobj( $id );
        my %eprint_contribs;
        foreach my $role (@{$repo->config( "orcid","eprint_fields" )})
        {
            $eprint_contribs{$role} = $eprint->value( $role );
        }

        my $users_orcid = $user->value( "orcid" );
        my $putcode = undef;
        my $result = undef;

        for my $key (keys %eprint_contribs)
        {
            foreach my $contributor (@{$eprint_contribs{$key}}){
                if( ($contributor->{orcid} eq $users_orcid) && defined($contributor->{putcode}) )
                {
                    $putcode = $contributor->{putcode};
                    last;
                }
            }
        }

        $result = EPrints::ORCID::AdvanceUtils::delete_orcid_record( $repo, $user, "DELETE", "/work/$putcode" );

        if( $result->is_success ) {
            # Remove putcode from eprint
            my %new_contributors;
            for my $key (keys %eprint_contribs)
            {
                $new_contributors{$key} = [];
                foreach my $contributor (@{$eprint_contribs{$key}})
                {
                    if( $contributor->{orcid} eq $users_orcid )
                    {
                        $contributor->{putcode} = undef;
                    }
                    push (@{$new_contributors{$key}}, $contributor);
                }
                $eprint->set_value( $key, $new_contributors{$key} );
            }

            $eprint->{orcid_update} = 1;
            $eprint->commit;
            $count_successful++;
        } else {
            $count_failed++;
        }
    }

    # Prepare user messages
    if( $count_successful > 0)
    {
        $db->save_user_message($current_user->get_value( "userid" ),
                "message",
                $self->html_phrase(
                    "deleted_in_orcid",
                    ("count_successful" => $repo->xml->create_text_node( $count_successful )),
                    ("count_all" => $repo->xml->create_text_node( $count_all )),
                ),
        );
    }

    if( $count_failed > 0)
    {
        $db->save_user_message($current_user->get_value( "userid" ),
    	        "error",
                $self->html_phrase(
            		"deleted_in_orcid_failed",
            		("count_failed" => $repo->xml->create_text_node( $count_failed )),
            		("count_all" => $repo->xml->create_text_node( $count_all )),
            	),
    	);
    }

	#finished so go home
	$repo->redirect( $repo->config( 'userhome' ) );
	exit;

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
    $frag->appendChild( $self->render_filter_duplicate_form( $xml, $query ) );

    my $hide_duplicates = 1;
    if( defined($query->param('hide_duplicates')) )
    {
        $hide_duplicates = $query->param('hide_duplicates');
    }

	#display records that might be exported
	my $dataset = $repo->dataset( "archive" );

	my $searchexp = $dataset->prepare_search( satisfy_all => 0 );
    foreach my $role (@{$repo->config( "orcid","eprint_fields" )})
    {
        $searchexp->add_field(
                fields => [
                $dataset->field($role.'_orcid')
            ],
            value => $orcid,
            match => "EX",
        );
    }
    my $results = $searchexp->perform_search;

    # Create a new list of items without a putcode for this user.
    if( $hide_duplicates )
    {
        my $ids = "";
        $results->map(sub{
            my( $session, $dataset, $eprint ) = @_;

            foreach my $role (@{$repo->config( "orcid","eprint_fields" )})
            {
                foreach my $c (@{ $eprint->value( $role ) })
                {
                    if( $c->{orcid} eq $user->value( "orcid" ) && !defined($c->{putcode}) )
                    {
                        $ids .= $eprint->id;
                        $ids .= " ";
                    }
                }
            }
        });

        if( $ids eq "" )
        {
            # All items have putcodes (are exported)
            $results = undef;
        }
        else
        {
        	my $new_search = $dataset->prepare_search();
            $new_search->add_field(
                fields => [ $dataset->field('eprintid') ],
                value => $ids,
                match => "IN",
                merge => "ANY",
                );
            my $new_results = $new_search->perform_search;
            $results = $new_results;
        }
    }

	if( defined($results) && $results->count > 0 ) #display records to be exported
	{
		#add the intro, export buttons and display the records
		$frag->appendChild( $self->render_orcid_export( $repo, $user, $xml, $results ) );
	}
    else
    {
        $frag->appendChild( $self->html_phrase( "no_items" ) );
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
    $filter_date_form->appendChild( $xml->create_element( "input", type => "submit", class => "ep_form_action_button filter", value => $self->phrase( "filter" ) ) );
    $filter_div->appendChild( $filter_date_form );
    return $filter_div;
}

sub render_filter_duplicate_form
{
    my( $self, $xml, $query ) = @_;
    my $duplicate_div = $xml->create_element( "div", class => "filter_duplicate" );
    my $filter_duplicate_form = $xml->create_element( "form", method => "get", action => "/cgi/users/home" );
    $filter_duplicate_form->appendChild( $xml->create_element( "input", type => "hidden", name => "screen", id => "screen", value => "ExportToOrcid") );

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
    $filter_duplicate_form->appendChild( $xml->create_element( "input", type => "submit", class => "ep_form_action_button filter", value => $self->phrase( "show_hide_duplicates" ) ) );
    $duplicate_div->appendChild( $filter_duplicate_form );
    return $duplicate_div;
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

    # deletion button
    my $button_delete = $btn_div->appendChild( $xml->create_element( "button",
        type => "submit",
        name => "_action_delete",
        class => "ep_form_action_button delete_button",
    ) );
    $button_delete->appendChild( $self->html_phrase( "delete" ) );

    # toggle switch
    my $toggle_button = $btn_div->appendChild( $xml->create_element( "button",
                    type => "button",
                    onclick => "toggleOrcidCheckbox();",
                    class => "ep_form_action_button toggle_button",
    ) );
    $toggle_button->appendChild( $self->html_phrase( "select" ) );

	$intro_div->appendChild( $help_div );
	$intro_div->appendChild( $btn_div );

	return $intro_div;
}

sub render_eprint_records
{
	my( $self, $xml, $records ) = @_;

    my $repo = $self->{repository};

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

		if( $filter_date && $mod_date < $filter_date )
        {
            my $date_format = $repo->config( "orcid_support_advance", "filter_format" ) || "%d/%m/%Y";
            $tr = $session->make_element( "tr", class => "filtered" );

            # work date
            $mod_date = strftime $date_format, gmtime( $mod_date->epoch );
            $td_citation->appendChild( $xml->create_text_node( "Last Modified: $mod_date" ) );
            $td_citation->appendChild( $xml->create_element("br"));

            $filter_date = strftime $date_format, gmtime( $filter_date->epoch );
            $td_citation->appendChild( $xml->create_text_node( "Filter date: $filter_date" ) );
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

    # deletion button
    my $button_delete = $btn_div->appendChild( $xml->create_element( "button",
            type => "submit",
            name => "_action_delete",
            class => "ep_form_action_button delete_button",
    ) );
    $button_delete->appendChild( $self->html_phrase( "delete" ) );

    # toggle switch
    my $toggle_button = $btn_div->appendChild( $xml->create_element( "button",
                    type => "button",
                    onclick => "toggleOrcidCheckbox();",
                    class => "ep_form_action_button toggle_button",
    ) );
    $toggle_button->appendChild( $self->html_phrase( "select" ) );

	return $btn_div;
}
