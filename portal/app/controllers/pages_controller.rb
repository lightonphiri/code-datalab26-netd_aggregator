# frozen_string_literal: true

# Static "About" page: project details and linked publications (config/publications.yml).
class PagesController < ApplicationController
  layout 'blacklight'

  def about
    @data = YAML.safe_load_file(Rails.root.join('config', 'publications.yml'))
  end
end
