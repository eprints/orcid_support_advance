###General ORCID Support Advance config###
$c->{orcid_support_advance}->{disable_input} = 1;

$c->{ORCID_contact_email} = $c->{adminemail};

$c->{orcid_support_advance}->{client_id} = "XXXX";
$c->{orcid_support_advance}->{client_secret} = "YYYY";

$c->{orcid_support_advance}->{orcid_apiv2} = "https://api.sandbox.orcid.org/v2.0/";
$c->{orcid_support_advance}->{orcid_org_auth_uri} = "https://sandbox.orcid.org/oauth/authorize";
$c->{orcid_support_advance}->{orcid_org_exch_uri} = "https://sandbox.orcid.org/oauth/token";
$c->{orcid_support_advance}->{orcid_org_revoke_uri} = "https://sandbox.orcid.org/oauth/revoke";
$c->{orcid_support_advance}->{redirect_uri} = $c->{"perl_url"} . "/orcid/authenticate";

# Decide if the pre-commit trigger should keep (0) or delete (1) non authenticated orcid ids,
# for example manual entries from using the "ORCID support" plugin.
# Set to 1 if (and only if!) repository user profiles (connected to orcid.org) are the sole source of ORCID data.
$c->{orcid_support_advance}->{destructive_trigger} = 0;

# The date to use when filtering works to import. 
# Should be one of the following options
# - last-modified-date
# - created-date
# - publication-date
$c->{orcid_support_advance}->{filter_date} = "publication-date";

# The EPrints User unique identifier field which maps to the contributors id field
$c->{orcid_support_advance}->{user_uid_field} = "email";

###Enable Screens###
$c->{"plugins"}->{"Screen::AuthenticateOrcid"}->{"params"}->{"disable"} = 0;
$c->{"plugins"}->{"Screen::ManageOrcid"}->{"params"}->{"disable"} = 0;
$c->{"plugins"}->{"Screen::ImportFromOrcid"}->{"params"}->{"disable"} = 0;
$c->{"plugins"}->{"Screen::ExportToOrcid"}->{"params"}->{"disable"} = 0;

###Enable Event Plugins###
$c->{"plugins"}->{"Event::OrcidSync"}->{"params"}->{"disable"} = 0;
$c->{"plugins"}->{"Event::CheckOrcidName"}->{"params"}->{"disable"} = 0;
$c->{"plugins"}->{"Event::UpdateCreatorOrcid"}->{"params"}->{"disable"} = 0;

####Enable Report Plugins###
$c->{plugins}{"Screen::Report::Orcid::CheckName"}{params}{disable} = 0;
$c->{plugin_alias_map}->{"Screen::Report::Orcid::UserOrcid"} = "Screen::Report::Orcid::UserPermsOrcid";
$c->{plugin_alias_map}->{"Screen::Report::Orcid::UserPermsOrcid"} = undef;

###Override DOI Import plugin###
$c->{plugin_alias_map}->{"Import::DOI"} = "Import::OrcidDOI";
$c->{plugin_alias_map}->{"Import::OrcidDOI"} = undef;

#Details of the organization for affiliation inclusion - the easiest way to obtain the RINGGOLD id is to add it to your ORCID user record manually, then pull the orcid-profile via the API and the identifier will be on the record returned.
$c->{"plugins"}->{"Event::OrcidSync"}->{"params"}->{"affiliation"} = {
    "organization" => {
        "name" => "My University Name", #name of organization - REQUIRED
        "address" => {
            "city" => "My Town",  # name of the town / city for the organization - REQUIRED if address included
            "region" => "Countyshire",  # region e.g. county / state / province - OPTIONAL
            "country" => "GB",  # 2 letter country code - AU, GB, IE, NZ, US, etc. - REQUIRED if address included
        },
        "disambiguated-organization" => {
            "disambiguated-organization-identifier" => "ZZZZ",  # replace ZZZZ with Institutional identifier from the recognised source
            "disambiguation-source" => "GRID", # Source for institutional identifier should be GRID or RINGGOLD (see https://www.grid.ac/institutes for GRID's free lookup service)
        }
    }   
};

###Education User Types###
##If the user type matches any of the following defined fields, update user's education affiliations rather than employment affiliations
$c->{orcid_support_advance}->{education_user_types} = [];

###User Roles###
push @{$c->{user_roles}->{admin}}, qw{
    +orcid_admin
};

###User fields###
$c->add_dataset_field('user',
    {
        name => 'orcid_access_token',
        type => 'text',
        show_in_html => 0,
        export_as_xml => 0,
        import => 0,
    },
    reuse => 1
);

$c->add_dataset_field('user',
    {
        name => 'orcid_granted_permissions',
        type => 'text',
        show_in_html => 0,
        export_as_xml => 0,
        import => 0,
    },
    reuse => 1
);

$c->add_dataset_field('user',
    {
        name => 'orcid_token_expires',
        type => 'time',
        render_res => 'minute',
        render_style => 'long',
        export_as_xml => 0,
        import => 0,
    },
    reuse => 1
);

$c->add_dataset_field('user',
    {
        name => 'orcid_read_record',
        type => 'boolean',
        show_in_html => 0,
        export_as_xml => 0,
        import => 0,
    },
    reuse => 1
);

$c->add_dataset_field('user',
    {
        name => 'orcid_update_works',
        type => 'boolean',
        show_in_html => 0,
        export_as_xml => 0,
        import => 0,
    },
    reuse => 1
);

$c->add_dataset_field('user',
    {
        name => 'orcid_update_profile',
        type => 'boolean',
        show_in_html => 0,
        export_as_xml => 0,
        import => 0,
    },
    reuse => 1
);

$c->add_dataset_field('user',
    {
        name => 'orcid_name',
        type => 'name',
        show_in_html => 0,
        export_as_xml => 0,
        import => 0,
    },
    reuse => 1
);

$c->add_dataset_field('user',
    {
        name => 'orcid_name_flag',
        type => 'boolean',
        show_in_html => 0,
        export_as_xml => 0,
        import => 0,
    },
    reuse => 1
);


###EPrint Fields###
#add put-code as a subfield to appropriate eprint fields
my $putcode_present = 0;
foreach my $field( @{$c->{fields}->{eprint}} )
{
    if( grep { $field->{name} eq $_ } @{$c->{orcid}->{eprint_fields}}) #$c->{orcid}->{eprint_fields} defined in z_orcid_support.pl
    {
        #check if field already has a putcode subfield
        $putcode_present = 0;
        for(@{$field->{fields}})
        {
            if( EPrints::Utils::is_set( $_->{name} ) && $_->{name} eq "putcode" )
            {
                $putcode_present = 1;
                last;
            }
        }

        if( !$putcode_present )
        {
            @{$field->{fields}} = (@{$field->{fields}}, (
                {
                    sub_name => 'putcode',
                    type => 'text',
                    allow_null => 1,
                    show_in_html => 0, #we don't need this field to appear in the workflow
                    export_as_xml => 0, #nor do we want it appearing in exports
                    can_clone => 0, #don't copy when using item as a template
                }
            ));
            # Possible to do: If that was successful, find and save putcodes of all items that have been exported in previous versions of this plugin.
        }
    }
}

#each permission defined below with some default behaviour (basic permission description commented by each item)
##default - 1 or 0 = this item selected or not selected on screen by default
##display - 1 or 0 = show or show not the option for this item on the screen at all
##admin-edit - 1 or 0 = admins can or can not change this option once users have obtained ORCID authorisation token
##user-edit - 1 or 0 = user can or can not change this option prior to obtaining ORCID authorisation token
##use-value = take the value for this option from the option of another permission e.g. include create if we get update
## **************** AVOID CIRCULAR REFERENCES IN THIS !!!! *******************
## Full Access is granted by the options not commented out below
$c->{ORCID_requestable_permissions} = [
    {
        "permission" => "/authenticate", # basic link to ORCID ID
        "default" => 1,
        "display" => 1,
        "admin_edit" => 0,
        "user_edit" => 0,
        "use_value" => "self",
        "field" => undef,
    },
    {
        "permission" => "/activities/update", # update research activities created by this client_id (implies create)
        "default" => 1,
        "display" => 1,
        "admin_edit" => 1,
        "user_edit" => 1,
        "use_value" => "self",
        "field" => "orcid_update_works",
       "sub_field" => "orcid_auto_update",
    },
    {
    "permission" => "/read-limited", # read information from ORCID profile which the user has set to trusted parties only
        "default" => 1,
        "display" => 1,
        "admin_edit" => 1,
        "user_edit" => 1,
        "use_value" => "self",
        "field" => "orcid_read_record",
    },
];

# work types mapping from EPrints to ORCID
# defined separately from the called function to enable easy overriding.
$c->{orcid_support_advance}->{"eprint_to_work_type_mapping"} = {
    "article" => "JOURNAL_ARTICLE",
    "book_section" => "BOOK_CHAPTER",
    "monograph" => "BOOK",
    "conference_item" => "CONFERENCE_PAPER",
    "book" => "BOOK",
    "thesis" => "DISSERTATION",
    "patent" => "PATENT",
    "artefact" => "OTHER",
    "exhibition" => "OTHER",
    "composition" => "OTHER",
    "performance" => "ARTISTIC_PERFORMANCE",
    "image" => "OTHER",
    "video" => "OTHER",
    "audio" => "OTHER",
    "dataset" => "DATA_SET",
    "experiment" => "OTHER",
    "teaching_resource" => "OTHER",
    "other" => "OTHER",
};

$c->{orcid_support_advance}->{"work_type_to_eprint_mapping"} = {
    "ARTISTIC_PERFORMANCE" => "performance",
    "BOOK_CHAPTER" => "book_section",
    "BOOK" => "monograph",
    "CONFERENCE_ABSTRACT" => "conference_item",
    "CONFERENCE_PAPER" => "conference_item",
    "CONFERENCE_POSTER" => "conference_item",
    "DATA_SET" => "dataset",
    "DISSERTATION" => "thesis",
    "EDITED_BOOK" => "book",
    "JOURNAL_ARTICLE" => "article",
    "MAGAZINE_ARTICLE" => "article",
    "NEWSLETTER_ARTICLE" => "article",
    "NEWSPAPER_ARTICLE" => "article",
    "OTHER" => "other",
    "PATENT" => "patent",
};

$c->{orcid_support_advance}->{"eprint_to_work_type"} = sub {
#return the ORCID work-type based on the EPrints item type.
##default EPrints item types mapped in $c->{"plugins"}{"Event::OrcidSync"}{"params"}{"work_type"} above.
##ORCID acceptable item types listed here: https://members.orcid.org/api/supported-work-types
##Defined as a function in case there you need to replace it for more complicated processing
##based on other-types or conference_item sub-fields
    my ( $eprint ) = @_;

    my %work_types = %{$c->{orcid_support_advance}{eprint_to_work_type_mapping}};

    if( defined( $eprint ) && $eprint->exists_and_set( "type" ))
    {
        my $ret_val = $work_types{ $eprint->get_value( "type" ) };
        if( defined ( $ret_val ) )
        {
            return $ret_val;
        }
    }

    # if no mapping found, call it 'OTHER'
    return "OTHER";
};

$c->{orcid_support_advance}->{"work_type_to_eprint"} = sub {
    my ( $type ) = @_;
	
    my %work_types = %{$c->{orcid_support_advance}{work_type_to_eprint_mapping}};

    if( defined( $type ) )
    {
        my $ret_val = $work_types{ $type };
        if( defined ( $ret_val ) )
        {
            return $ret_val;
        }
    }
    
    # if no mapping found, call it 'other'
    return "other";
};

# Add custom field mappings here i.e. if you have bespoke eprints fields which need mapping to orcid metadata
$c->{orcid_support_advance}->{"eprint_to_work_custom"} = sub {
        my ( $eprint, $work ) = @_;

       # EXAMPLE: Adding a doi as an external id, useful for Orcid.org detecting duplicates on profile
       #if ( $eprint->exists_and_set( "id_number" ) && EPrints::DOI->parse($eprint->get_value( "id_number" )) )
       #{
       #        my $doi = $eprint->get_value( "id_number" );
       #        push( @{$work->{"external-ids"}->{"external-id"}},
       #                {
       #                        "external-id-type" => "doi",
       #                        "external-id-value" => $doi,
       #                        "external-id-url" => "https://doi.org/$doi",
       #                        "external-id-relationship" => "SELF",
       #                }
       #        );
       #}

        return $work;
}

# contributor types mapping from EPrints to ORCID - used in Screen::ExportToOrcid to add contributor details to orcid-works and when importing works to eprints
$c->{orcid_support_advance}->{contributor_map} = {
    #eprint field name => ORCID contributor type,
    "creators" => "AUTHOR",
    "editors" => "EDITOR",
};

# map orcids work: citation-type to available import plugins
$c->{orcid_support_advance}->{import_citation_type_map} = {
    BIBTEX => "BibTeX",
};

# Adapted from: https://github.com/Ainmhidh/ORCID_Connect
# create a dataset for storing log information about orcid communications
# used to store and then check the state when making the OAuth connection
# and used to store repository based permissions (e.g. auto-exporting)
{
no warnings;

package EPrints::DataObj::OrcidLog;

@EPrints::DataObj::OrcidLog::ISA = qw( EPrints::DataObj );

sub get_dataset_id { "orcid_log" }

sub get_url { shift->uri }

sub get_defaults
{
        my( $class, $session, $data, $dataset ) = @_;

        $data = $class->SUPER::get_defaults( @_[1..$#_] );

        return $data;
}

}

$c->{datasets}->{orcid_log} = {
    sqlname => "orcid_log",
    class => "EPrints::DataObj::OrcidLog",
    index => 0,
};

$c->add_dataset_field('orcid_log',
    {
        name => 'id',
        type => "counter",
        sql_counter => "orcid_log",
    }
);

$c->add_dataset_field('orcid_log',
    {
        name => 'user',
        type => "int", 
    }
);

$c->add_dataset_field('orcid_log',
    {
        name => 'state',
        type => "text", 
    }
);

$c->add_dataset_field('orcid_log',
    {
        name => 'request_time',
        type => "int", 
    }
);

$c->add_dataset_field('orcid_log',
    {
        name => 'query',
        type => "longtext", 
    }
);

$c->add_dataset_field('orcid_log',
    {
        name => 'auto_update',
        type => "boolean", 
    }
);
