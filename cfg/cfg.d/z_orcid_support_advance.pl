
$c->{"plugins"}->{"Screen::ManageOrcid"}->{"params"}->{"disable"} = 0;

$c->{"plugins"}->{"Screen::ManageOrcid"}->{"params"}->{"orcid_org_auth_uri"} = "https://sandbox.orcid.org/oauth/authorize";
$c->{"plugins"}->{"Screen::ManageOrcid"}->{"params"}->{"orcid_org_exch_uri"} = "https://api.sandbox.orcid.org/oauth/token";
$c->{"plugins"}->{"Screen::ManageOrcid"}->{"params"}->{"redirect_uri"} = $c->{"perl_url"}."/orcid/authenticate";
$c->{"plugins"}->{"Screen::ManageOrcid"}->{"params"}->{"client_id"} = "XXXX";
$c->{"plugins"}->{"Screen::ManageOrcid"}->{"params"}->{"client_secret"} = "YYYY";



