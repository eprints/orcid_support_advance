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

#check to see if this work is already in the repository
sub check_work_presence
{
        my( $repo, $work ) = @_;

	#get the put code
	my $putcode = $work->{"put-code"};

	#search external ids for doi and urn
	my $doi;
    my $urn;
    my $ext_ids = $work->{'external-ids'}->{'external-id'};
    foreach my $ext_id ( @$ext_ids )
    {
        if( $ext_id->{'external-id-type'} eq "doi" )
        {
            $doi = $ext_id->{'external-id-value'};
        }
        elsif( $ext_id->{'external-id-type'} eq "urn" )
        {
            $urn = $ext_id->{'external-id-value'};
        }
	};

	#search for items that may have one of the ids
	my $ds = $repo->dataset( "archive" );
	my $searchexp = $ds->prepare_search( satisfy_all => 0 );
	$searchexp->add_field(
    		fields => [
			$ds->field('creators_putcode')
		],
		value => $putcode,
		match => "EQ", # EQuals
	);

	if( defined $doi )
	{
		$searchexp->add_field(
    			fields => [
				$ds->field('id_number')
			],
			value => $doi,
			match => "EQ", # EQuals
		);
	}

	if( defined $urn )
	{
		$searchexp->add_field(
    			fields => [
				$ds->field('id_number')
			],
			value => $urn,
			match => "EQ", # EQuals
		);
	}

	my $items = $searchexp->perform_search;
	if( $items->count > 0 )
	{
		return $items->ids( 0, 1 );
	}
	return 0;
}

sub read_orcid_works
{
	my( $repo, $user, $hide_duplicates ) = @_;
	my @works = ();
	my $response = EPrints::ORCID::AdvanceUtils::read_orcid_record( $repo, $user, "/works" );
	if( $response->is_success )
    {
        my $json = new JSON;
        my $json_text = $json->utf8->decode( $response->content );
		foreach my $work ( @{$json_text->{group}} )
		{
			#get the put-code
			my $work_summary = $work->{'work-summary'}[0];
			my $put_code = $work_summary->{'put-code'};
            my $existing_id = EPrints::ORCID::AdvanceUtils::check_work_presence( $repo, $work_summary );

    		# make a more detailed request if duplicates are allowed or record is not a duplicate
            if( !$hide_duplicates || ($hide_duplicates && !$existing_id) )
            {
    			my $work_response = EPrints::ORCID::AdvanceUtils::read_orcid_record( $repo, $user, "/work/$put_code" );
    		    if( $response->is_success )
    			{
    				my $work_json = $json->utf8->decode( $work_response->content );
                    if( $existing_id ) {
                        $work_json->{'$existing_id'} = $existing_id;
                    }
    				push @works, $work_json;
    			}
    			else
    			{
    				#couldn't retrieve work
    			}
            }
		}
	}
	else
	{
		#failed to read works summary
	}
	return \@works;

}

sub read_orcid_works_all_sources
{
	my( $repo, $user ) = @_;
	my @works = ();
	my $response = EPrints::ORCID::AdvanceUtils::read_orcid_record( $repo, $user, "/works" );
	if( $response->is_success )
	{
        	my $json = new JSON;
	        my $json_text = $json->utf8->decode( $response->content );
		foreach my $work ( @{$json_text->{group}} )
		{
    			push @works, $work;
   		}
	}
	return \@works;
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
	my( $repo, $user, $method, $item, $content ) = @_;

	my $uri = $repo->config( "orcid_support_advance", "orcid_apiv2") . $user->value( "orcid" ) . $item;

	my $req = HTTP::Request->new( $method, $uri );
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

#attempts to convert single string name provided by orcid.org into a creators name
sub get_name
{

	my ($in) = @_;

	my $DEBUG = 0;

	my ($honourific, $given, $family) = ('', '', ''); # what we are aiming for

	# trim leading and trailing white space
	$in =~ s/^\s+//;
	$in =~ s/[\s\r\n]+$//;

	# tidy up the use of ".", sometimes there is a following space, sometimes not
	$in =~ s/\./. /g;

	# compress white space sequence to a single space (may have happened due to the . processing)
	$in =~ s/\s+/ /g;

	# put . after each initial
	$in =~ s/([A-Z])\s/$1. /g;
	$in =~ s/\s([A-Z])$/ $1./;

	# encapsulate runs of initils, like "J. R. R." with a joining underscore
	$in =~ s/([A-Z])(\. | )/$1._/g;

	# put the last _ back to a space if there are more spaces - this bridges the initals to a 'middle' name
	$in =~ s/_([^_]+)$/ $1/;

	# honourifics can appear almost anywhere, they are a limited set, so find them and take them out up front
	if( $in =~ s/(Dr|Mr|Prof|Professor).?\s// ) { $honourific = $1 }

	# GSA specicific, but harmless in general
	# I've seen "." trail on some names, perhaps as a typo or an abbreviation "Ben."  Replace with an eye catcher to strip later
	$in =~ s/([a-z])\./$1:/g; # just match lower case non accented chars, remove this rule id th
	# trailing commas really confuse, remove
	$in =~ s/,$//;

	# key to this parser, does the input have a comma in it?
	if($in =~ /,/) # yes, then likely the input is like "Smith, John"
	{
		print "DEBUG comma:$in\n" if $DEBUG;
		($family, $given) = split(/, ?/, $in, 2);
	}
	elsif($in =~ /^[^\s]+$/) # there are no spaces in this input, like "Anderson", which may have been "Dr. Anderson"
	{
		print "DEBUG atomic:$in\n" if $DEBUG;
		$family = $in;
	}
	else # no comma, then likely the input is more like "John Smith"
	{
		# a common case is "Ben M. Ward", so bridge 'first' name with any initials, and further initials should already be joined
		$in =~ s/^([A-Z][a-z]+)\s([A-Z]\.)/${1}~${2}/;

		print "DEBUG plain:$in\n" if $DEBUG;

		# make the (UK based) assumption that a list of name parts is more like to contain several given names rather than several family names
		if( $in =~ /([^\s]+)\s/ ) # not-space space everything-else
		{
			$given = $1;
			$family = $';
		}
		else # something has gone wrong
		{
		$given = $family = "error";
		# $given = '';
		# $family = $in;
		}
	}

	$given =~ s/[~_]/ /g; # take out the first name joiner and nitials joiners
	$given =~ s/://g; # remove eye catcher
	$given =~ s/^([A-Z])$/$1./; # single lone initials seems to have been missed - bug in the above

	return ($honourific, $given, $family);
}

# loop through all of the orcidfor this eprint
# check if they've given permission to export
# start the export
sub auto_export_eprint
{
    my( $repo, $eprint ) = @_;

    # TODO: Other orcids beyond creators!!!!
    my @creators_orcids = @{$eprint->value( "creators_orcid" )};
    foreach my $creator_orcid( @creators_orcids )
    {
        my $user = EPrints::ORCID::Utils::user_with_orcid( $repo, $creator_orcid );
        if( defined $user && EPrints::ORCID::AdvanceUtils::check_permission( $user, "/activities/update" ) && $user->is_set( "auto_update" ) && $user->value( "auto_update" ) == 1 )
        {
            print STDERR "we can export this!!\n";
        }
        else
        {
            print STDERR "don't yet have permission to auto update\n";
        }
    }
}

1;
