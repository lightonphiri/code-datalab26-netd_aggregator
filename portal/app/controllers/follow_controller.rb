# frozen_string_literal: true

# "Follow this search" (SRS FR-60): Atom and RSS feeds of the newest additions for any search or set of filters.
# No account and no personal data: people use a feed reader, or a feed-to-email service of their choice.
class FollowController < ApplicationController
  include Blacklight::Configurable
  copy_blacklight_config_from(CatalogController)
  layout 'blacklight'

  def show
    @query = params.permit(:q, :search_field, f: {}).to_h
    feed = @query.merge(sort: 'added', per_page: 20)
    @atom = search_action_url(feed.merge(format: 'atom'))
    @rss = search_action_url(feed.merge(format: 'rss'))
    @results = search_action_path(@query.merge(sort: 'added'))
    @filters = (@query['f'] || {}).flat_map do |field, values|
      label = blacklight_config.facet_fields[field]&.display_label('facet') || field
      Array(values).map { |v| "#{label}: #{v}" }
    end
  end
end
