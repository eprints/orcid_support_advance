package EPrints::Plugin::Event::UpdateCreatorOrcid;

our @ISA = qw( EPrints::Plugin::Event );

use strict;
use utf8;
use EPrints;
use EPrints::Plugin::Event;
use EPrints::ORCID::AdvanceUtils;
use JSON;

sub update_creators
{
	my ( $self, $user ) = @_;

	#get user object for relevant details - check it exists and has appropriate fields
	my $repo = $self->{repository};
        die "Repository or User object not defined" unless (defined( $repo ) && defined( $user ));
        die "Orcid id or authorisation code not set for user ". $user->get_value( "userid" ) unless( $user->exists_and_set( "orcid" ) );

        if( $user->is_set( "email" ) )
        {
                my $email = $user->get_value( "email" );

                #get all records with this user's email listed as a creator
                my $ds = $repo->get_repository->get_dataset("eprint");
                my $search_exp = $ds->prepare_search();
                $search_exp->add_field(
                        fields => [ $ds->field( 'creators_id' ) ],
                        value => $email,
                );
                my $list = $search_exp->perform_search;
                $list->map(sub{
                        my($session, $dataset, $eprint) = @_;

                        my $creators = $eprint->get_value( 'creators' );
                        my @new_creators = ();
                        foreach my $c ( @{ $creators } )
                        {
                                if( EPrints::Utils::is_set( $c->{id} ) && $c->{id} eq $email ) #add orcid if creator email matches user email
                                {
                                        $c->{orcid} = $user->get_value( 'orcid' );
                                }
                                push @new_creators, $c;
                        }

                        #update creators field
                        $eprint->set_value( "creators", \@new_creators );
                        $eprint->commit;
                });
        }
        else
        {
                die "No email for user: " . $user->id;
        }

}
