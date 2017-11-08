=head1 NAME

EPrints::Plugin::Import::OrcidDOI

=cut

package EPrints::Plugin::Import::OrcidDOI;

# 10.1002/asi.20373

use strict;

use EPrints::Plugin::Import::DOI;
use URI;

our @ISA = qw/ EPrints::Plugin::Import::DOI /;


sub contributors
{
        my( $plugin, $data, $node ) = @_;

        my @creators;
 
	foreach my $contributor ($node->childNodes)
        {
                next unless EPrints::XML::is_dom( $contributor, "Element" );

                my $creator_name = {};
		my $creator_orcid;
                foreach my $part ($contributor->childNodes)
                {
                        if( $part->nodeName eq "given_name" )
                        {
                                $creator_name->{given} = EPrints::Utils::tree_to_utf8($part);
                        }
                        elsif( $part->nodeName eq "surname" )
                        {
                                $creator_name->{family} = EPrints::Utils::tree_to_utf8($part);
                        }
			elsif( $part->nodeName eq "ORCID" )
			{
 			       $creator_orcid = EPrints::ORCID::Utils::get_normalised_orcid( EPrints::Utils::tree_to_utf8($part) );
			}
                }

		if( exists $creator_name->{family} )
		{
			my $creator = { name => $creator_name };
			if( defined $creator_orcid )
			{
				$creator->{orcid} = $creator_orcid;
			}
	                push @creators, $creator;
		}
        }
        $data->{creators} = \@creators if @creators;
}

1;

=head1 COPYRIGHT

=for COPYRIGHT BEGIN

Copyright 2000-2011 University of Southampton.

=for COPYRIGHT END

=for LICENSE BEGIN

This file is part of EPrints L<http://www.eprints.org/>.

EPrints is free software: you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

EPrints is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
License for more details.

You should have received a copy of the GNU Lesser General Public
License along with EPrints.  If not, see L<http://www.gnu.org/licenses/>.

=for LICENSE END

