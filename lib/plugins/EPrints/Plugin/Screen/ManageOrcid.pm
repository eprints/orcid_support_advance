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

        $self->{actions} = [qw/ authenticate manage /];

        $self->{appears} = [
                {
                        place => "item_tools",
                        position => 100,
			action => "manage",
                },
		{
			place => "item_tools",
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
	if( !EPrints::Utils::is_set( $user->value( "orcid" ) ) )
	{
		return 1;
	}
	return 0;
}

sub action_authenticate
{
	my( $self ) = @_;

}

sub allow_manage
{
	my( $self ) = @_;

	my $user = $self->{session}->current_user;
	if( EPrints::Utils::is_set( $user->value( "orcid" ) ) )
	{
		return 1;	
	}
	return 0;
}

sub action_manage
{
	my( $self ) = @_;

}

sub render
{
	my( $self ) = @_;

        my $session = $self->{session};

        my $user = $session->current_user;

	#if user does not have an ORCID, ask them to autenticate one
	my $uri =  $session->config( "plugins" )->{"Screen::ManageOrcid"}->{"params"}->{"orcid_org_auth_uri"} . "?";
	$uri .= "client_id=" . uri_escape( $session->config( "plugins" )->{"Screen::ManageOrcid"}->{"params"}->{"client_id"} ) . "&";
	$uri .= "response_type=code&scope=/authenticate&";
	$uri .= "redirect_uri=" . $session->config( "plugins" )->{"Screen::ManageOrcid"}->{"params"}->{"redirect_uri"};

	print STDERR "uri....$uri\n";

	$session->redirect( $uri );
        $session->terminate();
        exit(0);


 #       my $chunk = $session->make_doc_fragment;
#	return $chunk;
}
