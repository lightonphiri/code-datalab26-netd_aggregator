# frozen_string_literal: true

# Static "About" page: project details and linked publications (config/publications.yml).
class PagesController < ApplicationController
  include Blacklight::Configurable
  copy_blacklight_config_from(CatalogController)
  layout 'blacklight'

  before_action { @data = YAML.safe_load_file(Rails.root.join('config', 'publications.yml')) }

  def about; end
  def faq; end
  def developers; end
  def contribute; end
  def api_docs; end

  def credits
    roles = @data['project']['members'].to_h { |m| [m['name'], m] }
    @contributors = @data['credits']['contributors'].map { |n| roles[n] || { 'name' => n } }
  end
end
