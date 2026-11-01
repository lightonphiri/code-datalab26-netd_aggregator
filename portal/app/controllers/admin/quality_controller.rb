# frozen_string_literal: true

module Admin
  # Metadata quality per institution (SRS FR-28): breakdown by element and suggested improvements. Admin only.
  class QualityController < BaseController
    def index
      @report = QualityReport.load
      respond_to do |format|
        format.html
        format.csv do
          send_data(QualityReport.to_csv(@report), filename: 'netd-metadata-quality-by-institution.csv', type: 'text/csv')
        end
        format.json { render json: @report || {} }
      end
    end
  end
end
