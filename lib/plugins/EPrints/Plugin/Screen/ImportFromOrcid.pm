=head1 NAME

EPrints::Plugin::Screen::ImportFromOrcid

=cut

package EPrints::Plugin::Screen::ImportFromOrcid;

use EPrints::Plugin::Screen;
use EPrints::ORCID::AdvanceUtils;
use JSON;
use Data::Dumper;

@ISA = ( 'EPrints::Plugin::Screen' );

use strict;

sub new
{
        my( $class, %params ) = @_;

        my $self = $class->SUPER::new(%params);

	$self->{actions} = [qw/ import /];

        $self->{appears} = [
		{
			place => "dataobj_view_actions",
			position => 100,
			action => "import",
		},
		{
			place => "item_tools",
			position => 100,
			action => "import",
		}
        ];

        return $self;
}

sub allow_import{

	my( $self ) = @_;
	
	my $user = $self->{repository}->current_user;
	
	return EPrints::ORCID::AdvanceUtils::check_permission( $user, "/read-limited" );
}

sub action_import{

}

sub render
{
	my( $self ) = @_;

        my $repo = $self->{repository};

        my $user = $repo->current_user;
	
	my $frag = $repo->xml->create_document_fragment();

	#display user's name
        my $user_title = $repo->xml->create_element( "h3", class => "orcid_subheading" );
        $user_title->appendChild( $self->html_phrase( "user_header", "user_name" => $user->render_value( "name" ) ) );
        $frag->appendChild( $user_title );

	#display user's orcid
	my $div = $repo->xml->create_element( "div", class => "orcid_id_display" );
        $div->appendChild( $user->render_value( "orcid" ) );
	$frag->appendChild( $div );

	#display records that might be imported
	my $response = EPrints::ORCID::AdvanceUtils::read_orcid_record( $repo, $user, "/works" );

	if( $response->is_success )
	{
		my $json = new JSON;
                my $json_text = $json->utf8->decode($response->content);
		$frag->appendChild( $self->render_orcid_records( $repo, $json_text ) );
	}
	else
	{
		#we've been unable to get a response from orcid for some reason
	}

	return $frag;
}

sub render_orcid_records
{
	my( $self, $repo, $json ) = @_;

	my $xml = $repo->xml;
	my $import_count = 0;
	my $ul = $xml->create_element( "ul", class => "orcid_imports" );
	foreach my $work ( @{$json->{group}} )
	{
		$ul->appendChild( $self->render_orcid_item( $repo, $xml, $work ) );		

	}
	return $ul;
}

sub render_orcid_item
{
	my( $self, $repo, $xml, $work ) = @_;
	
	my $li = $xml->create_element( "li", class => "orcid_item" );
	
	my $summary = $xml->create_element( "div", class => "orcid_summary" );

	my $work_summary = $work->{'work-summary'}[0];
	#render title
	my $title = $work_summary->{'title'}->{'title'}->{'value'};
	$summary->appendChild( $self->render_orcid_text( $xml, $title, "title" ) );

	#get date + type
	my $date = "";
        $date .= $work_summary->{'publication-date'}->{'day'}->{'value'} if $work_summary->{'publication-date'}->{'day'}->{'value'};
        $date .= "/".$work_summary->{'publication-date'}->{'month'}->{'value'} if $work_summary->{'publication-date'}->{'month'}->{'value'};
        $date .= "/".$work_summary->{'publication-date'}->{'year'}->{'value'} if $work_summary->{'publication-date'}->{'year'}->{'value'};
	
	#type
	my $type = $work_summary->{'type'};

	#date|type string
	my $date_type = "";
	$date_type .= $date if $date ne "";
	$date_type .= " | " if $date ne "" && defined $type;
	$date_type .= $type if defined $type;
	$summary->appendChild( $self->render_orcid_text( $xml, $date_type, "date-type" ) );

	#ext identifiers
	my $ext_ids = $work->{'external-ids'}->{'external-id'};
	my $id_ul = $xml->create_element( "ul", class => "external_identifiers" );
        foreach my $ext_id ( @$ext_ids )
        {
        	my $id_type = $ext_id->{'external-id-type'};
                my $id = $ext_id->{'external-id-value'};
		$id_ul->appendChild( $self->render_ext_id( $xml, $id_type, $id ) );
	}
	$summary->appendChild( $id_ul );	

	#source
	my $source = $work_summary->{'source'}->{'source-name'}->{'value'};
	$summary->appendChild( $self->render_orcid_text( $xml, "Source: $source", "source" ) );

	#import
	my $import = $xml->create_element( "div", class => "orcid_import" );
	my $form = $self->render_import_btn( $repo, $xml, $work_summary );
	$import->appendChild( $form ) if $form;


	$li->appendChild( $summary );
	$li->appendChild( $import );

	return $li;
}

sub render_orcid_text
{
	my( $self, $xml, $data, $class ) = @_;
	
	my $span = $xml->create_element( "div", class => $class );
	$span->appendChild( $xml->create_text_node( $data ) );
	return $span;
}

sub render_ext_id
{
	my( $self, $xml, $identifier, $value ) = @_;

	my $id_li = $xml->create_element( "li" );

	my $label = $xml->create_text_node( $identifier . ": " );
        my $link = $xml->create_element( "a", href=>$value, target=>"_blank" );	
	$link->appendChild( $xml->create_text_node( $value ) );

	$id_li->appendChild( $label );
	$id_li->appendChild( $link );
	
	return $id_li;
}

sub render_import_btn
{
	my( $self, $repo, $xml, $work_summary ) = @_;

	#only support DOI import for now
	my $doi;
	my $ext_ids = $work_summary->{'external-ids'}->{'external-id'};
        foreach my $ext_id ( @$ext_ids )
        {
                if( $ext_id->{'external-id-type'} eq "doi" )
		{
			$doi = $ext_id->{'external-id-value'};
			last;
		}
        }
	
	if( defined $doi )
	{	
		#reformat doi for import plugin
		$doi =~ s/^(http(s)?:\/\/(dx\.)?doi\.org\/)//i;

		#get import plugin
		my $import_plugin = "DOI";
	
		#render form
		my $form = $repo->render_form( "POST" );
		$form->appendChild( $repo->render_hidden_field ( "screen", "Import" ) );		
		$form->appendChild( $repo->render_hidden_field ( "_action_import_from", "Import" ) );		
		$form->appendChild( $repo->render_hidden_field ( "format", $import_plugin ) );		
		$form->appendChild( $repo->render_hidden_field ( "data", $doi ) );		
		my $button = $form->appendChild( $xml->create_element( "button", 
			type=>"submit", 
			name=>"Import_from_orcid", 
			value=>"Import_from_orcid" ) );
		$button->appendChild( $xml->create_text_node( "Import" ) );
		return $form;
	}
	else		
	{
		return 0;
	}
}
