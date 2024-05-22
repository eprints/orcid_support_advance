package EPrints::Plugin::Event::OrcidSync;

our @ISA = qw( EPrints::Plugin::Event );

use strict;
use utf8;
use EPrints;
use EPrints::Plugin::Event;
use EPrints::ORCID::AdvanceUtils;
use JSON;
use Storable qw(dclone);

#add institution to employment list - requires /activities/update scope
sub update_employment
{
	my ( $self, $user ) = @_;

	#get user object for relevant details - check it exists and has appropriate fields
	my $repo = $self->{repository};
    unless (defined( $repo ) && defined( $user ))
    {   
            $repo->log( "Repository or User object not defined" );
            return EPrints::Const::HTTP_INTERNAL_SERVER_ERROR;
    }
   
	unless( $user->exists_and_set( "orcid" ) && $user->exists_and_set( "orcid_access_token" ) )
    {
        $repo->log( "Orcid id or authorisation code not set for user ". $user->get_value( "userid" ) );
        return EPrints::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

	my $user_type = $user->get_value( "usertype" );
	my $affiliation = "employment";
	if( defined $user_type && grep( /^$user_type$/, @{$repo->config( "orcid_support_advance", "education_user_types" )} ) )
	{
		$affiliation = "education";
	}

	#get details for the communication from config - check they exist
	my $organisation = $repo->config( "plugins" )->{"Event::OrcidSync"}->{"params"}->{"affiliation"};
    unless ( defined( $organisation ))
    {
    	$repo->log( "Organization not defined correctly in configuration" );
        return EPrints::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

	#check if we have already created a profile on the ORCID record to determine whether to create or update the profile
	#NOTE: Assuming we are only maintaining one affiliation record as we have no historical detail over role / deparmental changes
	my $response = EPrints::ORCID::AdvanceUtils::read_orcid_record( $repo, $user, "/$affiliation" ."s" );

	if( $response->is_success )
        {
                my $json = new JSON;
                my $json_text = $json->utf8->decode($response->content);
		my $institution = $repo->config( "plugins" )->{"Event::OrcidSync"}->{"params"}->{"affiliation"}; #get our institution from the config

        # Add department
        if ( $user->is_set( "dept" ) )
        {
            my $institution_temp = dclone $institution;
            $institution_temp->{ "department-name" } = $user->get_value( "dept" );
            $institution = \%{$institution_temp};
        }

		#check this institution isn't already in the orcid.org list of employments
		my $add_institution = 1;
                foreach my $employment ( @{$json_text->{"$affiliation-summary"}} )
                {
			my $orgid1 = $institution->{'organization'}->{'disambiguated-organization'}->{'disambiguated-organization-identifier'};
        		my $orgid2 = $employment->{'organization'}->{'disambiguated-organization'}->{'disambiguated-organization-identifier'};
		        if( defined $orgid1 && defined $orgid2 && $orgid1 eq $orgid2 )
			{
		                $add_institution = 0;
		        }
                }

		#add the insitution if we still need to
		if( $add_institution )
        {
            my $result = EPrints::ORCID::AdvanceUtils::write_orcid_record( $repo, $user, "POST", "/$affiliation", $institution );
			if( $result->is_success )
			{
				return EPrints::Const::HTTP_OK;
			}
			else
			{
				#problem with the communication
				$repo->log( "Response from ORCID:".$response->code." ".$response->content );
                return EPrints::Const::HTTP_INTERNAL_SERVER_ERROR;
			}
                }
		else
		{
			#no need to add institution
			$repo->log( "[Event::OrcidSync::update_employment]Institution present in ORCID record. \n" );
			return EPrints::Const::HTTP_OK;
		}
        }
        else
        {
                #problem with the communication
        		$repo->log( "Response from ORCID:".$response->code." ".$response->content );
                return EPrints::Const::HTTP_INTERNAL_SERVER_ERROR;
        }	
}
