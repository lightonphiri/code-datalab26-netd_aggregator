# frozen_string_literal: true

# Year facet: newest year first, the latest SHOWN years visible and the rest behind "more »".
# Solr's facet.sort cannot sort values descending, so all years are requested and sorted here.
class YearFacetComponent < Blacklight::Facets::ListComponent
  SHOWN = 5

  def facet_item_presenters
    super.sort_by { |p| -p.value.to_i }
  end

  def items(range)
    facet_item_component_class.with_collection(facet_item_presenters[range] || [], wrapping_element: :li)
  end

  def collapse_id = "netd-more-#{@facet_field.key}"
end
