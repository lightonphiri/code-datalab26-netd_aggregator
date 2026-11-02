# frozen_string_literal: true
class SearchBuilder < Blacklight::SearchBuilder
  include Blacklight::Solr::SearchBuilderBehavior

  self.default_processor_chain += [:collapse_duplicates]

  # FR-19: a thesis deposited twice is listed once in results, facets and counts (the main record); the other
  # copies keep their record pages, which link to the main record. Fetches by id (bookmarks) are not filtered.
  def collapse_duplicates(solr_parameters)
    return if search_state.params[:q].is_a?(Hash)

    solr_parameters[:fq] = Array(solr_parameters[:fq]) + ['-duplicate_of_ssi:[* TO *]']
  end
end
