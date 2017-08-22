=head1 NAME

EPrints::Plugin::Screen::AuthenticateOrcid

=cut

package EPrints::Plugin::Screen::AuthenticateOrcid;

use EPrints::Plugin::Screen;

use URI::Escape;

@ISA = ( 'EPrints::Plugin::Screen' );

use strict;

sub new
{
        my( $class, %params ) = @_;

        my $self = $class->SUPER::new(%params);

        $self->{actions} = [qw/ authenticate /];

        $self->{appears} = [
		{
			place => "key_tools",
			position => 105,
			action => "authenticate",
		}
        ];

        return $self;
}

sub allow_authenticate
{
	my( $self ) = @_;
	
	my $user = $self->{session}->current_user;
	if( defined $user && !EPrints::Utils::is_set( $user->value( "orcid" ) ) )
	{
		return 1;
	}
	return 0;
}

sub action_authenticate
{
	my( $self ) = @_;

}

sub render
{
	my( $self ) = @_;

        my $session = $self->{session};

	my $action = $self->{processor}->{action};

        my $user = $session->current_user;

	#if user does not have an ORCID, ask them to autenticate one
	my $uri =  $session->config( "plugins" )->{"Screen::AuthenticateOrcid"}->{"params"}->{"orcid_org_auth_uri"} . "?";
	$uri .= "client_id=" . uri_escape( $session->config( "orcid_support_advance", "client_id" ) ) . "&";
	$uri .= "response_type=code&scope=/authenticate&";
	$uri .= "redirect_uri=" . $session->config( "plugins" )->{"Screen::AuthenticateOrcid"}->{"params"}->{"redirect_uri"};

	$session->redirect( $uri );
        $session->terminate();
        exit(0);


#       my $chunk = $session->make_doc_fragment;
#	return $chunk;
}
