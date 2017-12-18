=head1 NAME

EPrints::Plugin::Screen::ImportFromOrcid

=cut

package EPrints::Plugin::Screen::ImportFromOrcid;

use EPrints::Plugin::Screen;
use EPrints::ORCID::Utils;
use EPrints::ORCID::AdvanceUtils;
use JSON;

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

	#get screenid
	$self->{processor}->{screenid} = $self->{repository}->param( "screen" );

        #get selected works
        my @put_codes = $self->{repository}->param( "put-code" );
        $self->{processor}->{put_codes} = \@put_codes;
        
        #get appropriate user
        $self->{processor}->{user} = $repo->current_user;
        	
	my $userid = $self->{repository}->param( "dataobj" );
	my $ds = $repo->dataset( "user" );
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

	#in action import context, get user id from form, so we're definitely still working with the same user
	$self->{processor}->{orcid_user} = $ds->dataobj( $self->{repository}->param( "orcid_userid" ) ) if defined $self->{repository}->param( "orcid_userid" ); 
	
        #get works
        $self->{processor}->{works} = EPrints::ORCID::AdvanceUtils::read_orcid_works( $repo, $self->{processor}->{orcid_user} );
}

sub render
{
	my( $self ) = @_;

        my $repo = $self->{repository};
	my $xml = $repo->xml;

        my $user = $self->{processor}->{orcid_user};
	
	my $frag = $repo->xml->create_document_fragment();

	#display user's name
        my $user_title = $repo->xml->create_element( "h3", class => "orcid_subheading" );
        $user_title->appendChild( $self->html_phrase( "user_header", "user_name" => $user->render_value( "name" ) ) );
        $frag->appendChild( $user_title );

	#display user's orcid
	my $div = $repo->xml->create_element( "div", class => "orcid_id_display" );
        $div->appendChild( $user->render_value( "orcid" ) );
	$frag->appendChild( $div );

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

        #render help text
        my $help_div = $xml->create_element( "div", class => "import_intro_help" );
        $help_div->appendChild( $self->html_phrase( "import_help" ) );

        #render import button
        my $btn_div = $xml->create_element( "div", class => "import_intro_btn" );
        my $button = $btn_div->appendChild( $xml->create_element( "button",
                        type => "submit",
                        name => "_action_import",
                        class => "ep_form_action_button",
        ) );
        $button->appendChild( $xml->create_text_node( "Import" ) );

        $intro_div->appendChild( $help_div );
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

	return $btn_div;
}

sub render_orcid_records
{
	my( $self, $repo, $works ) = @_;

	my $xml = $repo->xml;
	my $import_count = 0;
	my $ul = $xml->create_element( "ul", class => "orcid_imports" );
	foreach my $work ( @{$works} )
	{
		$ul->appendChild( $self->render_orcid_item( $repo, $xml, $work ) );		

	}
	return $ul;
}

sub render_orcid_item
{
	my( $self, $repo, $xml, $work ) = @_;
	my $li = $xml->create_element( "li", class => "orcid_item" );
	
	my $summary = $xml->create_element( "div", class => "orcid_summary" );
	#render title
	my $title = $work->{'title'}->{'title'}->{'value'};
	$summary->appendChild( $self->render_orcid_text( $xml, $title, "title" ) );

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
		$id_ul->appendChild( $self->render_ext_id( $xml, $id_type, $id ) );
	}
	$summary->appendChild( $id_ul );	

	#source
	my $source = $work->{'source'}->{'source-name'}->{'value'};
	$summary->appendChild( $self->render_orcid_text( $xml, "Source: $source", "source" ) );

	#import
	my $import = $xml->create_element( "div", class => "orcid_import" );
	my $existing_id = $self->check_work_presence( $repo, $work ); 
	if( $existing_id )
	{
		$import->setAttribute( "class", "orcid_import warning" );
		$import->appendChild( $self->render_duplicate_record( $repo, $xml, $existing_id ) );
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
	my( $self, $xml, $identifier, $value ) = @_;

	my $id_li = $xml->create_element( "li" );

	my $label = $xml->create_text_node( $identifier . ": " );
        my $link = $xml->create_element( "a", href=>$value, target=>"_blank" );	
	$link->appendChild( $xml->create_text_node( $value ) );

	$id_li->appendChild( $label );
	$id_li->appendChild( $link );
	
	return $id_li;
}

sub render_duplicate_record
{
	my( $self, $repo, $xml, $existing_id ) = @_;
	my $div = $xml->create_element( "div", class => "duplicate_record" );

	#get duplicate record
	my $ds = $repo->dataset( "archive" );
	my $eprint = $ds->dataobj( @{$existing_id}[0] );
	$div->appendChild( $self->html_phrase( 
		"orcid_duplicate_record",
		title => $eprint->render_value( "title" )
	) );
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
	
	#create the eprint object
	my $eprint = $repo->dataset( 'eprint' )->create_dataobj({
		"eprint_status" => "buffer",
		"userid" => $user->get_value( "userid" ),											
	});
	
	if( defined( $work->{"type"} ) )
	{
		$eprint->set_value( "type", &{$repo->config( "plugins" )->{"Screen::ImportFromOrcid"}->{"work_type"}}( $work->{"type"} ) );
	}

	if( defined( $work->{"title"}->{"title"}->{"value"} ) )
	{
		$eprint->set_value( "title", $work->{"title"}->{"title"}->{"value"} );
	}

	if( defined( $work->{"journal-title"}->{"value"} ) )
	{
		$eprint->set_value( "publication" , $work->{"journal-title"}->{"value"} );
	}

	if( defined( $work->{"short-description"} ) )
	{
		$eprint->set_value( "abstract", $work->{"short-description"} );
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
				last;
			}
		}
	}
	
	#creators and editors
	my $creators;
	if( defined( $work->{"contributors"} ) )
	{
		foreach my $contributor (@{$work->{"contributors"}->{"contributor"}} )
		{
			my $username = undef;
			if( defined( $contributor->{"contributor-orcid"} ) )
			{
				#search for user with orcid and add username to eprint contributor if found
				my $orcid = $contributor->{"contributor-orcid"}->{"path"};
				my $user = EPrints::ORCID::Utils::user_with_orcid( $repo, $orcid );
			
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
						given => $given,
						family => $family,
					},
					orcid => $orcid,
				};
				$contributor->{"id"} = $user->get_value( "email" ) if defined $user;
			
				#add user to appropriate field
				if( $contrib_role eq "creators" )
				{
					push @{$creators}, $contributor;
				}
			}		
		}
	}
	$eprint->set_value( "creators", $creators );
	
	#put code
	my @put_codes = ( $work->{"put-code"} );
	$eprint->set_value( "orcid_put_codes", \@put_codes );

	#save the record
	$eprint->commit;
	return $eprint;
}

#chceck to see if this work is already in the repository
sub check_work_presence
{
        my( $self, $repo, $work ) = @_;
	
	#get doi
	my $doi;
        my $ext_ids = $work->{'external-ids'}->{'external-id'};
        foreach my $ext_id ( @$ext_ids )
        {
                if( $ext_id->{'external-id-type'} eq "doi" )
                {
                        $doi = $ext_id->{'external-id-value'};
			last
		}
	};
	
	#get the put code
	my $putcode = $work->{"put-code"};
	
	#search for items that may have the put code or doi
	my $ds = $repo->dataset( "archive" );
	my $searchexp = $ds->prepare_search( satisfy_all => 0 );
	$searchexp->add_field(
    		fields => [
			$ds->field('orcid_put_codes')
		],
		value => $putcode,
		match => "EQ", # EQuals
	);
	
	if( defined $doi )
	{
		$searchexp->add_field(
    			fields => [
				$ds->field('id_number')
			],
			value => $doi,
			match => "EQ", # EQuals
		);
	}
	
	my $items = $searchexp->perform_search;
	if( $items->count > 0 )
	{
		return $items->ids( 0, 1 );
	}
	return 0;
}
