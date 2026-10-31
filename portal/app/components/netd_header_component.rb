# frozen_string_literal: true

# Site header in the style of Columbia's Academic Commons: thin group bar, wordmark + search, link row.
class NetdHeaderComponent < Blacklight::Component
  def initialize(blacklight_config:)
    @blacklight_config = blacklight_config
  end

  def explore_path(level)
    helpers.search_action_path(f: { degree_level_ssim: [level] })
  end
end
