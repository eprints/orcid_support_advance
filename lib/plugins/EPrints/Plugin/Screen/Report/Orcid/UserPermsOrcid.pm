package EPrints::Plugin::Screen::Report::Orcid::UserPermsOrcid;

use EPrints::Plugin::Screen::Report::Orcid::UserOrcid;
our @ISA = ( 'EPrints::Plugin::Screen::Report::Orcid::UserOrcid' );

use strict;

sub bullet_points
{
        my( $self, $user ) = @_;

        my $repo = $self->{repository};

        my @bullets;

        if( $user->is_set( "orcid" ) )
        {
                push @bullets, EPrints::XML::to_string( $repo->html_phrase( "user_with_orcid", orcid => $repo->xml->create_text_node( $user->get_value( "orcid" ) ) ) );
        }

	#check through each permission defined in config
	foreach my $permission ( @{$repo->config( "ORCID_requestable_permissions" )} )
	{
		my $perm_name = $permission->{"permission"};
                if( $user->get_value( "orcid_granted_permissions" ) =~ m#$perm_name# )
                {
			 push @bullets, EPrints::XML::to_string( $repo->html_phrase( "report/userperms:$perm_name" ) );
		}
	}

        return @bullets;
}

                       
