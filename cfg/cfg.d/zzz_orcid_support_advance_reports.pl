#UserPermsOrcid Report
$c->{orcid_user}->{exportfields} = {
        user_report_core => [ qw(
        userid
        username
        name
        orcid
        usertype
        email
        dept
        org
        authenticate
        read
        update
    )],
};

$c->{orcid_user}->{exportfield_defaults} = [ qw(
        userid
        username
        name
        orcid
        usertype
        email
        dept
        org
        authenticate
        read
        update
)];

$c->{orcid_user}->{custom_export} = {
    authenticate => sub {
        my( $dataobj, $plugin ) = @_;
    
        my @perms;
        my $repo = $dataobj->repository;
        if( $dataobj->get_value( "orcid_granted_permissions" ) =~ m/\/authenticate/ )
        {
            return "Y";   
        }
        else
        {
            return "N";
        }
    },
    read => sub {
        my( $dataobj, $plugin ) = @_;
    
        my @perms;
        my $repo = $dataobj->repository;
        if( $dataobj->get_value( "orcid_granted_permissions" ) =~ m/\/read-limited/ )
        {
            return "Y";   
        }
        else
        {
            return "N";
        }
    },
    update => sub {
        my( $dataobj, $plugin ) = @_;
    
        my @perms;
        my $repo = $dataobj->repository;
        if( $dataobj->get_value( "orcid_granted_permissions" ) =~ m/\/activities\/update/ )
        {
            return "Y";   
        }
        else
        {
            return "N";
        }
    },
};

#CheckName Report
$c->{orcid_check_name}->{sortfields} = {
    "byname" => "name",
};

$c->{orcid_check_name}->{exportfields} = {
        user_report_core => [ qw(
        userid
        username
        name
        orcid
        orcid_name
    )],
};

$c->{orcid_check_name}->{exportfield_defaults} = [ qw(
        userid
        username
        name
        orcid
        orcid_name
)]; 

$c->{orcid_check_name}->{export_plugins} = $c->{user_report}->{export_plugins};
$c->{plugins}{"Screen::Report::Orcid::CheckName"}{params}{custom} = 1;
$c->{datasets}->{user}->{search}->{orcid_check_name} = $c->{search}->{user};

