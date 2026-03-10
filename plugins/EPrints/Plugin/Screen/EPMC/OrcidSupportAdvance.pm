package EPrints::Plugin::Screen::EPMC::OrcidSupportAdvance;

@ISA = ( 'EPrints::Plugin::Screen::EPMC' );

use strict;

sub new
{
    my( $class, %params ) = @_;

    my $self = $class->SUPER::new( %params );

    $self->{package_name} = 'orcid_support_advance';

    return $self;
}

sub action_enable
{
	my ($self, $skip_reload ) = @_;
	my $repo = $self->{repository};
	
	#only install if orcid field is present
	if( $repo->dataset( 'user' )->has_field( 'orcid' ) && $repo->dataset( 'user' )->field( 'orcid' )->type eq "orcid" )
	{
 		$self->SUPER::action_enable( $skip_reload );
	}
	else
	{
		$self->{processor}->add_message( "error", $repo->make_text( "Aborted: Requires 'ORCID Support' plugin to continue." ) ); 
		return;
	}
}
