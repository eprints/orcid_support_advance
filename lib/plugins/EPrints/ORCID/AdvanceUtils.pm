package EPrints::ORCID::AdvanceUtils;

use strict;
use utf8;
use LWP::Simple;
use LWP::UserAgent;
use URI::Escape;
use JSON;
use HTTP::Request::Common;
use Encode;


sub check_permission
{

	my( $user, $perm_name ) = @_;

	my @granted_permissions = split(" ", $user->get_value( "orcid_granted_permissions" ));
	if ( grep( /^$perm_name$/, @granted_permissions ) )
	{	
		return 1;
	}	
	return 0;

}

#build an authorisation uri to request an auth code for the given permissions - will redirecto cgi/orcid/authenticate
sub build_auth_uri
{
	
	my( $repo, @permissions ) = @_;

	my $uri =  $repo->config( "orcid_support_advance", "orcid_org_auth_uri" ) . "?";

        $uri .= "client_id=" . uri_escape( $repo->config( "orcid_support_advance", "client_id" ) ) . "&";
	
	my $scope = join "%20", @permissions;
        $uri .= "response_type=code&scope=$scope&";
        $uri .= "redirect_uri=" . $repo->config( "orcid_support_advance", "redirect_uri" );
	
	return $uri;
}

sub read_orcid_record
{
	my( $repo, $user, $item ) = @_;
	my $uri = $repo->config( "orcid_support_advance", "orcid_apiv2") . $user->value( "orcid" ) . $item;

	my $ua = LWP::UserAgent->new;
	my @headers = (
		'Accept' => 'application/json',
		'Authorization' => 'Bearer' . $user->value( "orcid_access_token" ),
	);
  
 	my $response = $ua->get( $uri, @headers );
	return $response;
}

sub write_orcid_record
{
	my( $repo, $user, $item, $content ) = @_;

	my $uri = $repo->config( "orcid_support_advance", "orcid_apiv2") . $user->value( "orcid" ) . $item;
	
	my $req = HTTP::Request->new( 'POST', $uri );
        my @headers = (
                'Content-type' => 'application/vnd.orcid+json',
                'Authorization' => 'Bearer ' . $user->value( "orcid_access_token" ),
		'Content-Lengh' => length( encode_utf8(to_json( $content ) ) ),
	);
	$req->header( @headers );
	$req->content( encode_utf8(to_json( $content ) ) );

	my $lwp = LWP::UserAgent->new;
	my $response = $lwp->request( $req );
	return $response;
}

1;
