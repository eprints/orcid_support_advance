package EPrints::Plugin::Screen::Report::Orcid::CheckName;

use EPrints::Plugin::Screen::Report::Orcid;
our @ISA = ( 'EPrints::Plugin::Screen::Report::Orcid' );

use strict;

sub new
{
    my( $class, %params ) = @_;

    my $self = $class->SUPER::new( %params );

    $self->{datasetid} = 'user';
    $self->{custom_order} = '-name';
    $self->{report} = 'orcid_check_name';
    $self->{searchdatasetid} = 'user';
    $self->{show_compliance} = 0;

    $self->{labels} = {
        outputs => "users"
    };

    $self->{sconf} = 'orcid_check_name';
    $self->{export_conf} = 'orcid_check_name';
    $self->{sort_conf} = 'orcid_check_name';
    $self->{group_conf} = 'orcid_check_name';

    return $self;
}

sub render
{
    my( $self ) = @_;

    my $repo = $self->repository;    
    my $chunk = $self->SUPER::render();

    $chunk->appendChild( $repo->make_javascript( <<JS ) );
Event.observe(window, 'load', function() {
    var checkboxes = document.querySelectorAll("input[type=checkbox][name=flag_name_mismatch]");
    checkboxes.forEach(function(checkbox) {
        checkbox.addEventListener('change', function() {
            // get userid from hidden sibling input element
            var div = this.parentNode;
            var input = div.querySelector("input[type=hidden]");

            // update the user record
            new Ajax.Request( '/cgi/orcid/flag_mismatch', {
                parameters: "userid="+input.value+"&checked="+this.checked,
                method: "POST",
                onSuccess: function() {
                    console.log( "flagged!" );
                }
            });
        });
    });
});
JS

    return $chunk;
}

# exclude anyone who has been flagged as not an issue
sub filters
{
    my( $self ) = @_;

    my @filters = @{ $self->SUPER::filters || [] };

    push @filters, { meta_fields => [ 'orcid_name_flag' ], value => 'FALSE', match => 'EX' };

    return \@filters;

}

sub items
{
    my( $self ) = @_;

    my $list = $self->SUPER::items();
    if( defined $list )
    {
        my @ids = ();

        $list->map(sub{
            my( $session, $dataset, $user ) = @_;

            my @problems = $self->validate_dataobj( $user );

            if( ( scalar( @problems ) > 0 ) && ( $user->is_set( "orcid" ) ) )
            {
                push @ids, $user->id;
            }
        });
        
        my $ds = $self->{session}->dataset( $self->{datasetid} );
        my $results = $ds->list(\@ids);
        return $results;

    }
    
    # we can't return an EPrints::List if {dataset} is not defined
    return undef;
}

sub ajax_user
{
    my( $self ) = @_;

    my $repo = $self->repository;

    my $json = { data => [] };
    $repo->dataset( "user" )
        ->list( [$repo->param( "user" )] )
        ->map(sub {
            (undef, undef, my $user) = @_;

            return if !defined $user; # odd

            my $frag = $user->render_citation_link;
            push @{$json->{data}}, {
                datasetid => $user->dataset->base_id,
                dataobjid => $user->id,
                summary => EPrints::XML::to_string( $frag ),
                #grouping => sprintf( "%s", $user->value( SOME_FIELD ) ),
                problems => [ $self->validate_dataobj( $user ) ],
            };
        });
    print $self->to_json( $json );
}

sub validate_dataobj
{
    my( $self, $user ) = @_;

    my $repo = $self->{repository};

    my @problems;

    # get user profile name and orcid name
    my $name = $user->get_value( "name" );
    my $orcid_name = $user->get_value( "orcid_name" );

    if( $name->{given} ne $orcid_name->{given} )
    {
        push @problems, EPrints::XML::to_string( $repo->html_phrase( "given_name_mismatch", given => $repo->xml->create_text_node( $orcid_name->{given} ) ) );
    }

    if( $name->{family} ne $orcid_name->{family} )
    {
        push @problems, EPrints::XML::to_string( $repo->html_phrase( "family_name_mismatch", family => $repo->xml->create_text_node( $orcid_name->{family} ) ) );
    }

    # if we have problems, add flag option to remove them
    if( scalar @problems > 0 )
    {
        my $frag = $repo->xml->create_document_fragment();

        $frag->appendChild( $repo->html_phrase( "flag_name_mismatch" ) );

        my $div = $frag->appendChild( $repo->make_element( "div", class => "flag_name_mismatch" ) );
 
        $div->appendChild( $repo->render_hidden_field( "userid", $user->id ) );

        my $checkbox = $div->appendChild( $repo->make_element( "input",
            type => "checkbox",
            name => "flag_name_mismatch",
            value => $user->value( "orcid_name_flag" ),
        ) );
        push @problems, EPrints::XML::to_string( $frag );
    }

    return @problems;
}
