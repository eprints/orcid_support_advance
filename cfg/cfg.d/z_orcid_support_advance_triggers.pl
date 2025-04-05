# trigger for acquiring a user's name from their orcid.org profile
$c->add_dataset_trigger( "user", EPrints::Const::EP_TRIGGER_BEFORE_COMMIT, sub {

    my( %params ) = @_;

    my $repo = $params{repository};
    my $user = $params{dataobj};

    if( $user->dataset->has_field( "orcid_name_flag" ) && !$user->is_set( "orcid_name_flag" ) )
    {
        $user->set_value( "orcid_name_flag", "FALSE" );
    }

    if( $user->is_set( "orcid" ) && $user->exists_and_set( "orcid_access_token" ) )
    {
        $repo->dataset( "event_queue" )->create_dataobj({
            pluginid => "Event::CheckOrcidName",
            action => "check_name",
            params => ["/id/user/".$user->get_value( "userid" )],
        });
    }
} );

#automatic update of eprint contributor fields - orcid should be set to user's orcid value
$c->add_dataset_trigger( 'eprint', EPrints::Const::EP_TRIGGER_BEFORE_COMMIT, sub
{
    my( %args ) = @_;
    my( $repo, $eprint, $changed ) = @args{qw( repository dataobj changed )};

    #contains "email" by default
    my $user_uid_field = $repo->config("orcid_support_advance", "user_uid_field");

    #contains "creators" and "editors" by default
    foreach my $role (@{$c->{orcid}->{eprint_fields}})
    {
        # Set some variables
        my $contributors_orcid = "$role" . "_orcid";
        my $contributors_id = "$role" . "_id";

        return unless $eprint->dataset->has_field( $contributors_orcid );

        if( !$eprint->{orcid_update} ) # this update hasn't come from orcid, therefore we want to check the orcids and put-codes
        {
            my $contributors = $eprint->get_value("$role");
            my @new_contributors;

            my $old_eprint = $eprint->dataset->dataobj( $eprint->id );
            my $old_contributors = $old_eprint->get_value( "$role" ) if defined $old_eprint;

            my $prev_ids = $changed->{"$contributors_id"};

            #loop through the existing contributors and update them
            foreach my $c (@{$contributors})
            {
                my $new_c = $c;

                # try to set orcid via user profile, keep/delete old orcid (depending on config)
                $new_c->{orcid} = undef if $repo->config( "orcid_support_advance", "destructive_trigger" );
                # get id and user profile
                my $c_id = $c->{id};
                $c_id = lc($c_id) if defined $c_id and $user_uid_field eq "email";

                my $user_ds = $repo->dataset( "user" );

                my $user_id = $repo->get_database->ci_lookup(
                    $user_ds->field( $user_uid_field ),
                    $c->{id}
                );

                my $results = $user_ds->search(
                    filters => [
                    {
                        meta_fields => [ ( $user_uid_field ) ],
                        value => $user_id, match => "EX"
                    }
                ]);

                my $user = $results->item( 0 );
                if( $user )
                {
                    if( EPrints::Utils::is_set( $user->value( 'orcid' ) ) ) # user has an orcid
                    {
                        # set the orcid
                        $new_c->{orcid} = $user->value( 'orcid' );
                    }
                }

                # need to update any put-codes associated with creators/editors
                if( defined($old_contributors) && @{$old_contributors} )
                {
                    # first delete any put-code we've carried over, but keep a record of an existing put-code
                    $new_c->{putcode} = undef;
                    if( defined $new_c->{orcid} )
                    {
                        #we have an orcid, so see if this orcid had a put code attached previously
                        foreach my $old_c ( @{$old_contributors} )
                        {
                            if( defined $old_c->{putcode} && $old_c->{orcid} eq $new_c->{orcid} )
                            {
                                $new_c->{putcode} = $old_c->{putcode};
                            }
                        }
                    }
                }
                # Drop contributors without name or id.
                # Effectively removes manually deleted entries where the orcid couldn't be removed since it's read-only
                push( @new_contributors, $new_c ) unless !$new_c->{id} && !$new_c->{name}->{family} && !$new_c->{name}->{given};
            }

            #now we have a list of new and old contributors, see if any put-codes have been removed and if so, remove those records from ORCID
            foreach my $old_c ( @{$old_contributors} )
            {
                my $seen = 0;
                foreach my $new_c( @new_contributors )
                {
                    if( defined $old_c->{putcode} && defined $new_c->{putcode} && $old_c->{putcode} eq $new_c->{putcode} )
                    {
                        $seen = 1;
                        last;
                    }
                }
                if( !$seen )
                {
                    # this record has been removed
                    # To Do: Think about deleting item in orcid record
                }
            }
            $eprint->set_value("$role", \@new_contributors);
        }
    }
}, priority => 60 );

# Update EPrint ORCID metadata when a user connects/disconnects their user account with orcid.org
$c->add_dataset_trigger( 'user', EPrints::Const::EP_TRIGGER_AFTER_COMMIT, sub
{
    my( %args ) = @_;
    my( $repo, $user, $changed ) = @args{qw( repository dataobj changed )};

    #contains "email" by default
    my $user_uid_field = $repo->config("orcid_support_advance", "user_uid_field");

    if( exists $changed->{orcid} && $user->is_set( $user_uid_field ) )
    {
        my $user_id = $user->value( $user_uid_field );
        my $ds = $repo->get_repository->get_dataset( "eprint" );

        my $search_exp = $ds->prepare_search( satisfy_all => 0 );
        foreach my $role (@{$repo->config( "orcid", "eprint_fields" )} )
        {
            $search_exp->add_field(
                fields => [ $ds->field( $role.'_id' ) ],
                value => $user_id,
            );
        }

        my $list = $search_exp->perform_search;

        $list->map( sub{
            my( $session, $dataset, $eprint ) = @_;
            $eprint->commit( 1 );
        } );
    }
}, priority => 50 );
