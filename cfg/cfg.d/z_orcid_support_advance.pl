###General ORCID Support Advance config###
$c->{ORCID_contact_email} = $c->{adminemail};

$c->{orcid_support_advance}->{client_id} = "XXXX";
$c->{orcid_support_advance}->{client_secret} = "YYYY";

$c->{orcid_support_advance}->{orcid_apiv2} = "https://api.sandbox.orcid.org/v2.0/";
$c->{orcid_support_advance}->{orcid_org_auth_uri} = "https://sandbox.orcid.org/oauth/authorize";
$c->{orcid_support_advance}->{orcid_org_exch_uri} = "https://api.sandbox.orcid.org/oauth/token";
$c->{orcid_support_advance}->{redirect_uri} = $c->{"perl_url"} . "/orcid/authenticate";

###Enable Screens###
$c->{"plugins"}->{"Screen::AuthenticateOrcid"}->{"params"}->{"disable"} = 0;
$c->{"plugins"}->{"Screen::ManageOrcid"}->{"params"}->{"disable"} = 0;
$c->{"plugins"}->{"Screen::ImportFromOrcid"}->{"params"}->{"disable"} = 0;

###ORCIDSync Event Plugin###
$c->{"plugins"}->{"Event::OrcidSync"}->{"params"}->{"disable"} = 0; # enable the updates plugin
#Details of the organization for affiliation inclusion - the easiest way to obtain the RINGGOLD id is to add it to your ORCID user record manually, then pull the orcid-profile via the API and the identifier will be on the record returned.
$c->{"plugins"}->{"Event::OrcidSync"}->{"params"}->{"affiliation"} = {
						"organization" => {
	                                                "name" => "My University Name", #name of organization - REQUIRED
        	                                        "address" => {
                	                                        "city" => "My Town",  # name of the town / city for the organization - REQUIRED if address included
							#	"region" => "Countyshire",  # region e.g. county / state / province - OPTIONAL
							        "country" => "GB",  # 2 letter country code - AU, GB, IE, NZ, US, etc. - REQUIRED if address included
                                        	        },
                                                	"disambiguated-organization" => {
                                                        	"disambiguated-organization-identifier" => "ZZZZ",  # replace ZZZZ with Institutional identifier from the recognised source
	                                                        "disambiguation-source" => "RINGGOLD", # Source for institutional identifier should be RINGGOLD or ISNI
        	                                        }
						}
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
		"permission" => "/authenticate",		#basic link to ORCID ID
		"default" => 1,
		"display" => 1,
		"admin_edit" => 0,
		"user_edit" => 0,
		"use_value" => "self",
		"field" => undef,
	},
	{
		"permission" => "/activities/update",		#update research activities created by this client_id (implies create)
		"default" => 1,
		"display" => 1,
		"admin_edit" => 1,
		"user_edit" => 1,
		"use_value" => "self",
		"field" => "orcid_update_works",
	},
	{
		"permission" => "/read-limited",	#read information from ORCID profile which the user has set to trusted parties only
		"default" => 1,
		"display" => 1,
		"admin_edit" => 1,
		"user_edit" => 1,
		"use_value" => "self",
		"field" => "orcid_read_record",
	},
];
