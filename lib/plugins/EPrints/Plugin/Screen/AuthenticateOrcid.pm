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
	
	return 0;

	#my $user = $self->{repository}->current_user;
	#if( defined $user && !EPrints::Utils::is_set( $user->value( "orcid" ) ) )
	#{
	#	return 1;
	#}
	#return 0;
}

sub action_authenticate
{
	my( $self ) = @_;

}

sub render
{
	my( $self ) = @_;

        my $repo = $self->{repository};
	
	my $uri = EPrints::ORCID::AdvanceUtils::build_auth_uri( $repo, ("/authenticate") );

	$repo->redirect( $uri );
        $repo->terminate();
        exit(0);
}
