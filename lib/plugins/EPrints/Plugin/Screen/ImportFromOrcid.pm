=head1 NAME

EPrints::Plugin::Screen::ImportFromOrcid

=cut

package EPrints::Plugin::Screen::ImportFromOrcid;

use EPrints::Plugin::Screen;

use EPrints::ORCID::AdvanceUtils;

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
	my $response = EPrints::ORCID::AdvanceUtils::read_works( $repo, $user );

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
	my $table = $xml->create_element( "table", class => "ep_upload_fields ep_multi" );
	foreach my $work ( @{$json->{group}} )
	{
		my $work_summary = $work->{'work-summary'}[0];
		my $date = "";
                $date .= $work_summary->{'publication-date'}->{'day'}->{'value'} if $work_summary->{'publication-date'}->{'day'}->{'value'};
                $date .= "/".$work_summary->{'publication-date'}->{'month'}->{'value'} if $work_summary->{'publication-date'}->{'month'}->{'value'};
                $date .= "/".$work_summary->{'publication-date'}->{'year'}->{'value'} if $work_summary->{'publication-date'}->{'year'}->{'value'};

		my $title = $work_summary->{'title'}->{'title'}->{'value'};

		$table->appendChild( $self->render_table_row_with_text( $xml, "Title", $title, 1 ) );
                $table->appendChild( $self->render_table_row_with_text( $xml, "Date", $date ) );

		my $ext_ids = $work->{'external-ids'}->{'external-id'};
                foreach my $ext_id ( @$ext_ids )
                {
                        my $id_type = $ext_id->{'external-id-type'};
                        my $id = $ext_id->{'external-id-value'};
                        $table->appendChild( $self->render_table_row_with_import( $xml, $id_type, $id, $id_type, $id, $import_count++ ) );
                }
                my $url  = $work->{'url'}->{'value'};
                $table->appendChild( $self->render_table_row_with_link( $xml, "URL", $url, $url ) );
	}
	return $table;
}

sub render_table_row
{
        my( $self, $xml, $label, $value, $link, $first ) = @_;
        my $tr = $xml->create_element( "tr", style=>"width: 100%" );
        my $first_class = "";
        $first_class = "_first" if $first;
        my $td1 = $tr->appendChild( $xml->create_element( "td", class=>"ep_orcid_works_label".$first_class ) );
        my $td2 = $tr->appendChild( $xml->create_element( "td", class=>"ep_orcid_works_value".$first_class ) );
        my $td3 = $tr->appendChild( $xml->create_element( "td", class=>"ep_orcid_works_link".$first_class ) );
        $td1->appendChild( $label );
        $td2->appendChild( $value );
        $td3->appendChild( $link );

        return $tr;
}

sub render_table_row_with_text
{
        my( $self, $xml, $label_val, $value_val, $first ) = @_;

        my $label = $xml->create_text_node( $label_val );
        my $value = $xml->create_text_node( $value_val );
        my $link = $xml->create_text_node( "" );
        return $self->render_table_row( $xml, $label, $value, $link, $first );
}

sub render_table_row_with_link
{
        my( $self, $xml, $label_val, $value_val, $link_val ) = @_;

        my $label = $xml->create_text_node( $label_val );
        my $value = $xml->create_element( "a", href=>$link_val, target=>"_blank" );
        $value->appendChild( $xml->create_text_node( $value_val ) );
        my $link = $xml->create_text_node( "" );
        return $self->render_table_row( $xml, $label, $value, $link );
}

sub render_table_row_with_import
{
        my( $self, $xml, $label_val, $disp_val, $import_type, $import_value, $import_count ) = @_;

        my $plugin_map = {
                "doi" => "DOI",
                "BIBTEX" => "BibTeX",
                "PMID" => "PubMedID",
        };

        my $repo = $self->{session};
        my $label = $xml->create_text_node( $label_val );
        my $value = $xml->create_text_node( $disp_val );

        my $import_plugin = $plugin_map->{$import_type};

        my $form = $repo->render_form( "POST" );
        $form->appendChild( $repo->render_hidden_field ( "screen", "Import" ) );
        $form->appendChild( $repo->render_hidden_field ( "_action_import_from", "Import" ) );
        $form->appendChild( $repo->render_hidden_field ( "format", $import_plugin ) );
        $form->appendChild( $repo->render_hidden_field ( "data", $import_value ) );
        $form->setAttribute("id", "orcid_import_form_".$import_count);
        my $button = $form->appendChild( $xml->create_element( "button",
                        form=>"orcid_import_form_".$import_count,
                        type=>"submit",
                        name=>"Import_from_orcid",
                        value=>"Import_from_orcid" ) );
        $button->setAttribute( "disabled", "disabled" ) unless $import_plugin;
        $button->appendChild( $xml->create_text_node( "Import" ) );
        return $self->render_table_row( $xml, $label, $value, $form );
}
