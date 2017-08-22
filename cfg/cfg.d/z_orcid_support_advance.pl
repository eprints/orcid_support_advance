
$c->{orcid_support_advance}->{client_id} = "XXXX";
$c->{orcid_support_advance}->{client_secret} = "YYYY";

$c->{"plugins"}->{"Screen::AuthenticateOrcid"}->{"params"}->{"disable"} = 0;

$c->{"plugins"}->{"Screen::AuthenticateOrcid"}->{"params"}->{"orcid_org_auth_uri"} = "https://sandbox.orcid.org/oauth/authorize";
$c->{"plugins"}->{"Screen::AuthenticateOrcid"}->{"params"}->{"orcid_org_exch_uri"} = "https://api.sandbox.orcid.org/oauth/token";
$c->{"plugins"}->{"Screen::AuthenticateOrcid"}->{"params"}->{"redirect_uri"} = $c->{"perl_url"}."/orcid/authenticate";



