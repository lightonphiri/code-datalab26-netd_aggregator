# frozen_string_literal: true

# Public metadata quality page (SRS FR-28): overall completeness and ETD-MS compliance, by origin of each value.
# The per-institution breakdown is in the admin panel (Admin::QualityController) until agreed with HEA.
class QualityController < ApplicationController
  include Blacklight::Configurable
  copy_blacklight_config_from(CatalogController)
  layout 'blacklight'

  def index
    @report = QualityReport.public(QualityReport.load)
    respond_to do |format|
      format.html
      format.csv { send_data(QualityReport.to_csv(@report), filename: 'netd-metadata-quality.csv', type: 'text/csv') }
      format.json { render json: @report || {} }
    end
  end
end
