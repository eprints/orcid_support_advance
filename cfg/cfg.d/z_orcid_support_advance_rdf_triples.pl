##############################
# Contributors
##############################

$c->add_dataset_trigger( "eprint", EP_TRIGGER_RDF, sub {
	my( %o ) = @_;
	my $eprint = $o{"dataobj"};
	my $eprint_uri = "<".$eprint->uri.">";

	my $all_people = {};

	# authors

	my @creators;
	if( $eprint->dataset->has_field( "creators" ) && $eprint->is_set( "creators" ) )
	{
		@creators = @{$eprint->get_value( "creators" )};
	}
	my $authors_uri = "<".$eprint->uri."#authors>";
	for( my $i=1; $i<=@creators; ++$i )
	{
		my $creator_uri = &{$c->{rdf}->{person_uri}}( $eprint, $creators[$i-1] );

		$o{"graph"}->add(
			secondary_resource => $creator_uri,
		   	  subject => $eprint_uri,
		 	predicate => "dct:creator",
		    	   object => $creator_uri );
		$o{"graph"}->add(
			secondary_resource => $creator_uri,
		   	  subject => $eprint_uri,
		 	predicate => "bibo:authorList",
		    	   object => $authors_uri );
		$o{"graph"}->add(
			secondary_resource => $creator_uri,
		   	  subject => $authors_uri,
		 	predicate => "rdf:_$i",
		    	   object => $creator_uri );
		$all_people->{$creator_uri} = $creators[$i-1];
	}

	# editors

	my @editors;
	if( $eprint->dataset->has_field( "editors" ) && $eprint->is_set( "editors" ) )
	{
		@editors = @{$eprint->get_value( "editors" )};
	}
	my $editors_uri = "<".$eprint->uri."#editors>";
	for( my $i=1; $i<=@editors; ++$i )
	{
		my $editor_uri = &{$c->{rdf}->{person_uri}}( $eprint, $editors[$i-1] );
		$o{"graph"}->add(
			secondary_resource => $editor_uri,
		   	  subject => $eprint_uri,
		 	predicate => "<http://www.loc.gov/loc.terms/relators/EDT>",
		    	   object => $editor_uri );
		$o{"graph"}->add(
			secondary_resource => $editor_uri,
		   	  subject => $eprint_uri,
		 	predicate => "bibo:editorList",
		    	   object => $editors_uri );
		$o{"graph"}->add(
			secondary_resource => $editor_uri,
		   	  subject => $editors_uri,
		 	predicate => "rdf:_$i",
		    	   object => $editor_uri );
		$all_people->{$editor_uri} = $editors[$i-1];
	}

	# other contributors

	my @contributors;
	if( $eprint->dataset->has_field( "contributors" ) && $eprint->is_set( "contributors" ) )
	{
		@contributors = @{$eprint->get_value( "contributors" )};
	}
	foreach my $contributor ( @contributors )
	{
		my $contributor_uri = &{$c->{rdf}->{person_uri}}( $eprint, $contributor );
		$o{"graph"}->add(
			secondary_resource => $contributor_uri,
		   	  subject => $eprint_uri,
		 	predicate => "<".$contributor->{type}.">",
		    	   object => $contributor_uri );
		$all_people->{$contributor_uri} = $contributor;
	}

	# Contributors names

	foreach my $person_uri ( keys %{$all_people} )
	{
		my $e_given = $all_people->{$person_uri}->{name}->{given} || "";
		my $e_family = $all_people->{$person_uri}->{name}->{family} || "";

		$o{"graph"}->add(
			secondary_resource => $person_uri,
		   	  subject => $person_uri,
		 	predicate => "rdf:type",
		    	   object => "foaf:Person" );
		$o{"graph"}->add(
			secondary_resource => $person_uri,
		   	  subject => $person_uri,
		 	predicate => "foaf:givenName",
		    	   object => $e_given,
			     type => "xsd:string" );
		$o{"graph"}->add(
			secondary_resource => $person_uri,
		   	  subject => $person_uri,
		 	predicate => "foaf:familyName",
		    	   object => $e_family,
			     type => "xsd:string" );
		$o{"graph"}->add(
			secondary_resource => $person_uri,
		   	  subject => $person_uri,
		 	predicate => "foaf:name",
		    	   object => "$e_given $e_family",
			     type => "xsd:string" );

  		if( EPrints::Utils::is_set( $all_people->{$person_uri}->{orcid} ) )
    		{
  			$o{"graph"}->add(
				secondary_resource => $person_uri,
				subject => $person_uri,
				predicate => "owl:sameAs",
				object => "https://orcid.org/" . $all_people->{$person_uri}->{orcid},
				type => "foaf:Person" );
    		}
	}

	# Corporate Creators
	my @corp_creators;
	if( $eprint->dataset->has_field( "corp_creators" ) && $eprint->is_set( "corp_creators" ) )
	{
		@corp_creators = @{$eprint->get_value( "corp_creators" )};
	}
	foreach my $corp_creator ( @corp_creators )
	{
		my $org_uri = &{$c->{rdf}->{org_uri}}( $eprint, $corp_creator );
		next unless $org_uri;
		$o{"graph"}->add(
			secondary_resource => $org_uri,
		   	  subject => $org_uri,
		 	predicate => "rdf:type",
		    	   object => "foaf:Organization" );
		$o{"graph"}->add(
			secondary_resource => $org_uri,
		   	  subject => $org_uri,
		 	predicate => "foaf:name",
		    	   object => $corp_creator,
			     type => "xsd:string" );
		$o{"graph"}->add(
			secondary_resource => $org_uri,
		   	  subject => $eprint_uri,
		 	predicate => "dct:creator",
		    	   object => $org_uri );
	}
		
} );
