# frozen_string_literal: true

# Institution facet that also lists registry institutions with no harvested ETDs (count 0).
class InstitutionFacetComponent < Blacklight::Facets::ListComponent
  def render? = true

  def missing_institutions
    return [] if filtered?

    InstitutionRegistry.names - @facet_field.paginator.items.map(&:value)
  end

  # Show at most `limit` rows in total; zero rows beyond that go behind a "more" toggle.
  def visible_slots
    [(facet_config.limit || 10) - @facet_field.paginator.items.size, 0].max
  end

  def collapse_id = "netd-more-#{@facet_field.key}"

  # Hide the zero rows once the user has filtered by an institution
  def filtered?
    @facet_field.search_state.filter(@facet_field.key).any?
  rescue StandardError
    false
  end
end
