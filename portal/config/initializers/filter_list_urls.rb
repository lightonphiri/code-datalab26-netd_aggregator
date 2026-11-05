# frozen_string_literal: true

# Readable filter-list addresses (FR-71): every link Blacklight builds to the full list of one filter (the "more"
# link, the filter box in its pop-up, A-Z and count sorting, next and previous pages) goes through url_for with
# action "facet" and the Solr field as id; the field is swapped for its readable name, e.g. field-of-study.
module FilterListUrls
  def url_for(options = nil)
    if options.respond_to?(:to_h) && !options.is_a?(String)
      h = options.respond_to?(:to_unsafe_h) ? options.to_unsafe_h : options.to_h
      if h.with_indifferent_access[:action].to_s == 'facet' && h.with_indifferent_access[:id].present?
        h = h.with_indifferent_access
        h[:id] = FilterSlug.slug(h[:id]) unless h[:only_values]
        return super(h)
      end
    end
    super
  end
end

ActionView::RoutingUrlFor.prepend(FilterListUrls)
