package EPrints::Plugin::Event::CheckOrcidName;

our @ISA = qw( EPrints::Plugin::Event );

use strict;
use utf8;
use EPrints;
use EPrints::Plugin::Event;
use EPrints::ORCID::AdvanceUtils;
use JSON;

#add institution to employment list - requires /activities/update scope
sub check_name
{
	my ( $self, $user ) = @_;

	#get user object for relevant details - check it exists and has appropriate fields
	my $repo = $self->{repository};
	die "Repository or User object not defined" unless (defined( $repo ) && defined( $user ));
	die "Orcid id or authorisation code not set for user ". $user->get_value( "userid" ) unless( $user->exists_and_set( "orcid" ) && $user->exists_and_set( "orcid_access_token" ) );

	#get the user's name from ORCID
	my $response = EPrints::ORCID::AdvanceUtils::read_orcid_record( $repo, $user, "/person" );
        if( $response->is_success )
        {
                my $json = new JSON;
                my $json_text = $json->utf8->decode($response->content);

                #get their orcid.org name
                my $orcid_given = $json_text->{"name"}->{"given-names"}->{"value"};
                my $orcid_family = $json_text->{"name"}->{"family-name"}->{"value"};

                my $name = $user->get_value( "orcid_name" );

                if( $orcid_given ne $name->{given} || $orcid_family ne $name->{family} )
                {
                        $user->set_value( "orcid_name", {
                                family => $orcid_family,
                                given => $orcid_given,
                        });

                        $user->commit;
                }
        }
        else
        {
                #problem with the communication
                die "Response from ORCID:".$response->code." ".$response->content;
        }
}
