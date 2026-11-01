# frozen_string_literal: true

require 'csv'

# Public metadata quality dashboard (SRS FR-28): completeness and ETD-MS compliance per institution, by where each
# value comes from. Reads the report written by `netd.cli quality-report` after every scheduled run.
class QualityController < ApplicationController
  include Blacklight::Configurable
  copy_blacklight_config_from(CatalogController)
  layout 'blacklight'

  GROUPS = {
    'repository' => ['In the repository element', 'Supplied by the institution\'s repository in the proper metadata element'],
    'elsewhere' => ['Elsewhere in the repository', 'Supplied by the repository, but only in collection names or free text'],
    'portal' => ['Filled by the portal', 'Read from the PDF by the portal\'s models, or corrected by the portal team'],
    'missing' => ['Missing', 'No value']
  }.freeze

  def index
    @report = load_report
    respond_to do |format|
      format.html
      format.csv { send_data(to_csv, filename: 'netd-metadata-quality.csv', type: 'text/csv') }
      format.json { render json: @report || {} }
    end
  end

  private

  def load_report
    JSON.parse(File.read(File.join(Harvester::LOGS, 'quality.json')))
  rescue Errno::ENOENT, JSON::ParserError
    nil
  end

  def to_csv
    CSV.generate do |csv|
      csv << ['institution', 'records', 'element', 'etd_ms_element', 'in_repository_element_pct', 'elsewhere_in_repository_pct',
              'filled_by_portal_pct', 'missing_pct']
      (@report&.dig('institutions') || []).each do |i|
        i['elements'].each do |e|
          csv << [i['name'], i['records'], e['label'], e['etdms'], e['repository'], e['elsewhere'], e['portal'], e['missing']]
        end
      end
    end
  end
end
