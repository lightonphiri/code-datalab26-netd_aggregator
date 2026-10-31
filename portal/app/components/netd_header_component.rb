# frozen_string_literal: true

# Site header in the style of Columbia's Academic Commons: thin group bar, wordmark + search, link row (About, Explore).
class NetdHeaderComponent < Blacklight::Component
  def initialize(blacklight_config:)
    @blacklight_config = blacklight_config
  end
end
