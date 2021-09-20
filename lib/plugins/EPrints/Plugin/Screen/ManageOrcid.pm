=head1 NAME

EPrints::Plugin::Screen::ManageOrcid

=cut

package EPrints::Plugin::Screen::ManageOrcid;

use EPrints::Plugin::Screen;

use URI::Escape;

@ISA = ( 'EPrints::Plugin::Screen' );

use strict;

sub new
{
    my( $class, %params ) = @_;

    my $self = $class->SUPER::new(%params);

    $self->{actions} = [qw/ manage connect_to_orcid disconnect /];

    $self->{appears} = [
        {
            place => "key_tools",
            position => 105,
            action => "manage",
        }
    ];

    return $self;
}

sub render_title
{
    my( $self ) = @_;

    my $user = $self->{repository}->current_user;
    if( EPrints::Utils::is_set( $user->value( "orcid" ) && EPrints::Utils::is_set( $user->value( "orcid_granted_permissions" ) ) ) )
    {
        return $self->html_phrase( "title" );
    }
    else
    {
        return $self->html_phrase( "orcid/connect" );
    }
}

# managing permissions can only be done by the current user about the current user - admin cannot change the permissions a user has given orcid.org
sub can_be_viewed
{
    my( $self ) = @_;

    return $self->allow_manage;
}

sub allow_connect_to_orcid { return $_[0]->can_be_viewed; }

sub allow_manage
{
    my( $self ) = @_;

    my $user = $self->{repository}->current_user;

    if( defined $user )
    {
        return 1;
    }
    return 0;
}

sub allow_disconnect { return $_[0]->can_be_viewed; }

sub action_manage
{
    my( $self ) = @_;
}

# called when first connecting to ORCID or when updating permissions
sub action_connect_to_orcid
{
    my( $self ) = @_;

    my $repo = $self->{repository};
    my $user = $repo->current_user;

    # check to see if we already hold permissions and if so revoke them before setting the new ones
    my $proceed = 1;
    if( $user->exists_and_set( "orcid_granted_permissions" ) )
    {
        my $response = $self->revoke_permissions( $user );
        $proceed = 0 if !$response->is_success;
    }

    if( $proceed )
    {
        my @permissions = @{$repo->config( "ORCID_requestable_permissions" )};

        my @request_permissions = ( "/authenticate" );
        foreach my $permission ( @permissions )
        {
            my $perm_name = $permission->{ "permission" };
            if( defined( $repo->param( $perm_name ) ) )
            {
                push @request_permissions, $perm_name;
            }
        }

        # build a state value from the userid and the current timestamp
        my $state = substr( "00000000".$user->get_value( "userid" ), -8 );
        my $timestamp = EPrints::Time::datetime_utc( EPrints::Time::utc_datetime() );
        $state .= $timestamp;
        $state = uri_escape( dec_to_base_36( $state ) ); # converted to base36 for a shorter string and less apparent what the data is

        my $uri = EPrints::ORCID::AdvanceUtils::build_auth_uri( $repo, $state, @request_permissions );

        $repo->redirect( $uri );

        # create a log record for this authentication request
        my $log_ds = $repo->dataset( "orcid_log" );
        my $log_data = {};
        $log_data->{"user"} = $user->get_value( "userid" );
        $log_data->{"state"} = $state;
        $log_data->{"request_time"} = $timestamp;
        $log_data->{"query"} = $uri;

        # include any local repository permissions
        $log_data->{"auto_update"} = 1 if defined $repo->param( "orcid_auto_update" );

        my $log_entry = $log_ds->create_dataobj( $log_data );
        $log_entry->commit();

        $repo->terminate();
        exit(0);
    }
    else
    {
        # we had problems dealing with revoking existing permissions
        my $db = $repo->database;
        $db->save_user_message( $user->get_value( "userid" ),
            "error",
            $repo->html_phrase( "Plugin/Screen/ManageOrcid:failed_pre_connection" )
        );
    }
}

sub action_disconnect
{
    my( $self ) = @_;

    my $repo = $self->{repository};
    my $user = $repo->current_user;

    if( defined ( $user ) )
    {
        my $db = $repo->database;

        my $response = $self->revoke_permissions( $user );
        if( $response->is_success )
        {
            $db->save_user_message( $user->get_value( "userid" ),
                "message",
                $repo->html_phrase( "Plugin/Screen/ManageOrcid:disconnected" )
            );
        }
        else
        {
            # we haven't delisted the organization as a trusted user yet, so keep details so we can try again some time
            $db->save_user_message( $user->get_value( "userid" ),
                "error",
                $repo->html_phrase( "Plugin/Screen/ManageOrcid:failed_disconnecting_orcid" )
            );
        }
    }
}

sub revoke_permissions
{
    my( $self, $user ) = @_;

    my $repo = $self->{repository};

    # before we remove our codes and permissions, we need to revoke the repository as a trusted organization
    my $uri = $repo->config( "orcid_support_advance", "orcid_org_revoke_uri" );
    my $ua = LWP::UserAgent->new;
    my $params = {
        "client_id" => $repo->config( "orcid_support_advance", "client_id" ),
        "client_secret" => $repo->config( "orcid_support_advance", "client_secret" ),
        "token" => $user->value( "orcid_access_token" ),
    };        

    my $response = $ua->post( $uri, $params );
    if( $response->is_success )
    {
        # we can wipe the details from the user
        $user->set_value( "orcid", undef );
        $user->set_value( "orcid_auth_code", undef );
        $user->set_value( "orcid_token_expires", undef );
        $user->set_value( "orcid_granted_permissions", undef );
        $user->set_value( "orcid_access_token", undef );
        $user->set_value( "orcid_name", undef );
        $user->set_value( "orcid_auto_update", undef );
        $user->commit();
    }
    return $response;
}

sub render
{
    my( $self ) = @_;

    my $repo = $self->{repository};

    my $action = $self->{processor}->{action};

    my $user = $repo->current_user;

    my $frag = $repo->xml->create_document_fragment();
    
    my $user_title = $repo->xml->create_element( "h3", class => "orcid_subheading" );
    $user_title->appendChild( $self->html_phrase( "user_header", "user_name" => $user->render_value( "name" ) ) );
    $frag->appendChild( $user_title );	

    # display initial connect message
    if( ! ( EPrints::Utils::is_set( $user->value( "orcid" ) && EPrints::Utils::is_set( $user->value( "orcid_granted_permissions" ) ) ) ) )
    {
        $frag->appendChild( $self->html_phrase( "orcid_initial_connect" ) );
    }

    # add link to info page
    $frag->appendChild( $self->html_phrase( "orcid_info" ) );

    # add details of ORCID permissions we hold for this user
    $frag->appendChild( $self->render_held_permissions( $repo, $user ) );

    # form to update local permissions
    $frag->appendChild( $self->render_local_permissions( $repo, $user ) );

    return $frag;
}

sub render_held_permissions
{
    my ( $self, $repo, $user ) = @_;

    my $held_frag = $repo->xml->create_document_fragment();

    # if we hold permissions from ORCID, display the user's ORCID Details and list the granted permissions
    if( $user->exists_and_set( "orcid_granted_permissions" ) )
    {
        # Display the ORCID
        my $div = $repo->xml->create_element( "div", class => "orcid_id_display" );
        $div->appendChild( $user->render_value( "orcid" ) );

        $held_frag->appendChild( $div );

        # Display the granted permissions list
        $held_frag->appendChild( $self->html_phrase( "granted_permissions" ) );
        my $ul = $repo->xml->create_element( "ul", class=>"permissions_list" );

        # make an array of granted permissions
        my @granted_permissions = split( " ", $user->get_value( "orcid_granted_permissions" ) );

        # check through each permission defined in config
        foreach my $permission ( @{$repo->config( "ORCID_requestable_permissions" )} )
        {
            my $perm_name = $permission->{"permission"};
            if( $user->get_value( "orcid_granted_permissions" ) =~ m#$perm_name# )
            {
                # make list element for this permission if it was granted
                my $list_item = $repo->xml->create_element( "li" );
                $list_item->appendChild( $self->html_phrase( "permission:$perm_name" ) );
                $ul->appendChild( $list_item );

                # Remove permission from granted permissions checklist
                for( my $x = 0; $x < @granted_permissions; $x++ )
                {
                    if( $granted_permissions[$x] eq $perm_name )
                    {
                        splice( @granted_permissions, $x, 1 );
                        last;
                    }   
                }
            }
        }

        $held_frag->appendChild( $ul );

        my $held_div = $repo->xml->create_element( "div", class => "orcid_user_info" );
        # Display how long these permissions are due to last, in the local timezone.
        my $localtime = EPrints::Time::datetime_utc( EPrints::Time::split_value( $user->get_value( "orcid_token_expires" ) ) );
        $held_div->appendChild( $self->html_phrase( "permissions_instructions", 
            expiry_date => $repo->xml->create_text_node( EPrints::Time::human_time( $localtime ) ) )
        );

        $held_frag->appendChild($held_div);
    }
    return $held_frag;
}

sub render_local_permissions
{
    my ( $self, $repo, $user ) = @_;

    my $local_frag = $repo->xml->create_document_fragment();
    my $local_perms_div = $repo->xml->create_element( "div", "class" => "local_perms_div" );

    # create form headers for changes submission.
    my $local_perms_form = $repo->render_form( "POST" );
    $local_perms_form->appendChild( $repo->render_hidden_field( "screen", $self->{processor}->{screenid} ) );
    $local_perms_form->appendChild( $repo->render_hidden_field( "user", $user->get_value( "userid" ) ) );
    $local_perms_form->setAttribute( "id", "orcid_local_perms_form" );

    # Work through the permissions listed in config to render them, checking them against the user's granted permissions

    my @permissions = @{$repo->config( "ORCID_requestable_permissions" )};
    foreach my $permission ( @permissions )
    {
        my $perm_name = $permission->{"permission"};
        my $selected = 0;
        my $disabled = 0;

        # check the permission is set to display
        if( $permission->{"display"} )
        {
            # check the field is editable
            if( !$permission->{user_edit} )
            {
                $disabled = 1;
            }

            # check the setting for the user
            if( EPrints::ORCID::AdvanceUtils::check_permission( $user, $perm_name ) )
            {
                $selected = 1;
            }

            my $input = $repo->xml->create_element( "input",
                class => "ep_form_input_checkbox",
                name => $permission->{"permission"},
                type => "checkbox",
                value => 1,
            );
            
            if( $selected || !$user->exists_and_set( "orcid_granted_permissions" ) ) # set true if selected or connecting for first time
            {
                $input->setAttribute( "checked", "checked" );
            }

            if( $disabled )
            {
                $input->setAttribute( "disabled", "disabled" );
            }
            
            $local_perms_div->appendChild( $input );
            my $permission_title = $repo->xml->create_element( "span", "class" => "orcid_permission_title" );
            $permission_title->appendChild( $self->html_phrase( $permission->{"permission"}."_select_text" ) );
            $local_perms_div->appendChild( $permission_title ); #$self->html_phrase($permission->{"permission"}."_select_text"));
            my $description = $repo->xml->create_element( "div", class => "permission_description" );
            $description->appendChild( $self->html_phrase( $permission->{"permission"}."_select_description" ) );
            $local_perms_div->appendChild( $description );

            # display extra subfields
            if( $permission->{"permission"} eq "/activities/update" )
            {
                $local_perms_div->appendChild( $self->render_permission_sub_field( $repo, $user, $permission ) );
            }
        }
    }
    
    $local_perms_form->appendChild($local_perms_div);
    
    my $connect_button = $repo->xml->create_element( "button",
        type=>"submit",
        class => "ep_form_action_button manage_orcid_button",
        name=>"_action_connect_to_orcid",
        value=>"do",
        id=>"connect-orcid-button",
    );

    $connect_button->appendChild( $repo->xml->create_element( "img", src=>"/images/orcid_id.svg", id=>"orcid-id-logo", width=>24, height=>24, alt=>"ORCID logo" ) );
    $connect_button->appendChild($self->html_phrase( "local_user_connect_orcid_button" ));
    $local_perms_form->appendChild($connect_button);
    
    #my $admin_button = $repo->xml->create_element( "button",
    #   type=>"submit",
    #   class => "ep_form_action_button",
    #   name=>"_action_update_local_user_perms",
    #   value=>"do",
    #);
    #$admin_button->appendChild($self->html_phrase( "admin_local_user_perms_button" ));
    #$local_perms_form->appendChild($admin_button);
    
    my $disconnect_button = $repo->xml->create_element( "button",
        type=>"submit",
        class => "ep_form_action_button danger manage_orcid_button",
        name=>"_action_disconnect",
        value=>"do",
        onclick=>"if(!confirm(\"".EPrints::Utils::tree_to_utf8($self->html_phrase( "confirm_erase_dialog" ))."\")) return false;",
    );
    $disconnect_button->appendChild($self->html_phrase( "admin_disconnect_button" ));
    $local_perms_form->appendChild($disconnect_button);
    
    $local_frag->appendChild($local_perms_form);

    return $local_frag;
}

sub render_permission_sub_field
{
    my( $self, $repo, $user, $permission ) = @_;

    my $sub_field_div = $repo->xml->create_element( "div", "class" => "sub_field_div" );

    my $sub_field = $permission->{sub_field};
    my $parent_permission = $permission->{permission};

    my $selected = 0;
    my $disabled = 0;

    # check the field is editable
    if( !$permission->{user_edit} )
    {
        $disabled = 1;
    }

    # check if the field is set
    if( $user->value( $sub_field ) )
    {
        $selected = 1;
    }

    # construct input
    my $input = $repo->xml->create_element( "input",
        class => "ep_form_input_checkbox",
        name => $sub_field,
        type => "checkbox",
        value => 1,
    );

    if( $selected || !$user->exists_and_set( "orcid_granted_permissions" ) ) # set true if selected or connecting for first time
    {
        $input->setAttribute( "checked", "checked" );
    }

    $sub_field_div->appendChild( $input );

    # title and description of sub field
    my $permission_title = $repo->xml->create_element( "span", "class" => "orcid_permission_title" );
    $permission_title->appendChild( $self->html_phrase( $parent_permission."_".$sub_field."_select_text" ) );
    $sub_field_div->appendChild( $permission_title ); 

    my $description = $repo->xml->create_element( "div", class => "permission_description" );
    $description->appendChild( $self->html_phrase( $parent_permission."_".$sub_field."_select_description" ) );
    $sub_field_div->appendChild( $description );

    return $sub_field_div;
}

sub dec_to_base_36
{
    # convert an integer from base 10 to base 36
    my ( $value ) = @_;
    return 0 unless ($value > 0);
    my @nums = (0..9,'a'..'z');
    my $retval = "";
    while ( $value > 0 )
    {
        $retval = $nums[$value % 36] .$retval;
        $value = int( $value / 36 );
    }
    return $retval;
}
