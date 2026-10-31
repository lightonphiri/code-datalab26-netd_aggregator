# frozen_string_literal: true

# Discovery configuration for the Zambia National ETD Portal (netd.ac.zm).
# Field names follow the harvester's Solr mapping (harvester/netd/index.py).
class CatalogController < ApplicationController
  include Blacklight::Catalog

  configure_blacklight do |config|
    config.header_component = NetdHeaderComponent
    config.default_solr_params = { rows: 20 }
    config.per_page = [20, 50, 100]

    # ---- results list --------------------------------------------------
    config.index.title_field = 'title_tsim'
    config.index.document_component = EtdResultComponent
    # (no index fields: the result line is laid out by EtdResultComponent, Academic Commons style)

    # ---- record page ----------------------------------------------------
    config.show.title_field = 'title_tsim'
    config.show.document_component = EtdShowComponent
    config.add_show_field 'author_tsim', label: 'Author', link_to_facet: 'author_ssim'
    config.add_show_field 'supervisor_tsim', label: 'Supervisor', link_to_facet: 'supervisor_ssim'
    config.add_show_field 'institution_ssim', label: 'Institution', link_to_facet: true
    config.add_show_field 'faculty_tsim', label: 'Faculty / School', link_to_facet: 'faculty_ssim'
    config.add_show_field 'department_tsim', label: 'Department', link_to_facet: 'department_ssim'
    config.add_show_field 'degree_level_ssim', label: 'Degree level', link_to_facet: true
    config.add_show_field 'degree_ssim', label: 'Degree', link_to_facet: true
    config.add_show_field 'discipline_tsim', label: 'Programme / Discipline', link_to_facet: 'discipline_ssim'
    config.add_show_field 'year_ssim', label: 'Year', link_to_facet: true
    config.add_show_field 'subject_tsim', label: 'Subjects', link_to_facet: 'subject_ssim', separator_options: { words_connector: '; ', last_word_connector: '; ', two_words_connector: '; ' }
    config.add_show_field 'language_ssim', label: 'Language'
    config.add_show_field 'abstract_tesim', label: 'Abstract'

    # ---- facets ----------------------------------------------------------
    config.add_facet_field 'institution_ssim', label: 'Institution', limit: 10, collapse: false,
                                              component: InstitutionFacetComponent
    config.add_facet_field 'full_text_ssim', label: 'Full text', collapse: false
    config.add_facet_field 'degree_level_ssim', label: 'Degree level', collapse: false
    config.add_facet_field 'faculty_ssim', label: 'Faculty / School', limit: 10
    config.add_facet_field 'department_ssim', label: 'Department', limit: 10
    config.add_facet_field 'discipline_ssim', label: 'Programme / Discipline', limit: 10
    config.add_facet_field 'degree_ssim', label: 'Degree', limit: 10
    config.add_facet_field 'supervisor_ssim', label: 'Supervisor', limit: 10
    config.add_facet_field 'subject_ssim', label: 'Subject', limit: 15
    config.add_facet_field 'year_ssim', label: 'Year', limit: 200, sort: 'index', component: YearFacetComponent
    config.add_facet_field 'author_ssim', label: 'Author', show: false
    config.add_facet_fields_to_solr_request!

    # ---- search fields -----------------------------------------------------
    config.add_search_field 'all_fields', label: 'All fields'
    { 'title' => 'Title', 'author' => 'Author', 'supervisor' => 'Supervisor', 'subject' => 'Subject' }.each do |key, label|
      config.add_search_field(key, label: label) do |field|
        field.solr_parameters = { 'spellcheck.dictionary': key == 'supervisor' ? 'default' : key,
                                  qf: "${#{key}_qf}", pf: "${#{key}_pf}" }
      end
    end

    # ---- sorting -------------------------------------------------------------
    # Sort control next to the result count (the default tools were dropped when this file was rewritten)
    config.add_results_collection_tool(:sort_widget)

    # Sort options as on Columbia's Academic Commons (FR-22)
    config.add_sort_field 'relevance', sort: 'score desc, year_isi desc, title_ssort asc', label: 'Best Match'
    config.add_sort_field 'latest', sort: 'year_isi desc, title_ssort asc', label: 'Published Latest'
    config.add_sort_field 'earliest', sort: 'year_isi asc, title_ssort asc', label: 'Published Earliest'
    config.add_sort_field 'title_az', sort: 'title_ssort asc, year_isi desc', label: 'Title A-Z'
    config.add_sort_field 'title_za', sort: 'title_ssort desc, year_isi desc', label: 'Title Z-A'

    config.spell_max = 5
    config.autocomplete_enabled = false
  end
end
