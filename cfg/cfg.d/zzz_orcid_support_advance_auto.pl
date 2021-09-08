$c->{orcid_support_advance}->{update_fields} = [qw(
    title
    type
    publication
    abstract
    date
    creators
    id_number
    doi
    urn
    isbn
    official_url
    monograph_type
    thesis_type
    ispublished
    place_of_pub
    event_title
    book_title
    editors
    institution
    note
    number
    pagerange
    publisher
    series
    volume
    keywords
)];

# auto-export permission field
$c->add_dataset_field('user',
    {
        name => 'auto_update',
        type => 'boolean',
        show_in_html => 0,
        export_as_xml => 0,
        import => 0,
    },
    reuse => 1
);

# run the auto export procedure for items being moved in to the live archive
$c->add_dataset_trigger( 'eprint', EPrints::Const::EP_TRIGGER_STATUS_CHANGE, sub{

    my( %args ) = @_;
    my( $repo, $eprint, $old_status, $new_status ) = @args{qw( repository dataobj old_status new_status )};

    if( defined $eprint && $new_status eq "archive" )
    {
        print STDERR "we've just gone live!!!\n";
    }
}, priority => 100 );


# run auto export procedure if item is in the live archive and if any relevant fields have changed
$c->add_dataset_trigger( 'eprint', EPrints::Const::EP_TRIGGER_BEFORE_COMMIT, sub{

    my( %args ) = @_;
    my( $repo, $eprint, $changed ) = @args{qw( repository dataobj changed )};

    return unless $eprint->value( "eprint_status" ) eq "archive";

    # check to see if any of fields that we use when export to orcid have been changed
    my $update_orcid = 0;
    foreach my $field ( @{$repo->config( "orcid_support_advance", "update_fields" )} )
    {
        if( exists $changed->{$field} )
        {
            $update_orcid = 1;
            last;
        }
    }

    # check the contributor map too, as it's also used when converting an eprint to an orcid work
    if( !$update_orcid )
    {
        my %contributor_mapping = %{$repo->config( "orcid_support_advance", "contributor_map" )};
        foreach my $contributor_role (  keys %contributor_mapping )
        {
            if( exists $changed->{$contributor_role} )
            {
                $update_orcid = 1;
                last;
            }
        }
    }

    return unless $update_orcid;

    print STDERR "we want to update this on orcid!!!\n";
}, priority => 70 );
