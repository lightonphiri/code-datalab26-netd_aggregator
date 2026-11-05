# frozen_string_literal: true

module Admin
  # Reports for HEA (SRS FR-63): signed-in administrators only (Lighton, November 2, 2026). The form page offers the
  # predefined reports (per institution, by supervisor) and custom reports; each runs as an HTML preview, Excel or PDF.
  # Every report run is written to the activity log.
  class EtdReportsController < BaseController
    KINDS = %w[institution supervisors custom].freeze
    PREVIEW_ROWS = 100
    PERMITTED = [:institution, :year_from, :year_to, :degree_level, :type, :faculty, :department, :fos_field,
                 :supervisor, :words, :usage, :list, :group, :then_by, :report_title, { columns: [] }].freeze

    def index
      fq = [HeaReport::MAIN]
      @institutions = InstitutionRegistry.all.select { |i| i[:source] }
      @values = %w[degree_level_ssim type_ssim faculty_ssim department_ssim fos_field_ssim].to_h do |f|
        [f, HeaReport.facet(f, fq, missing: false, sort: 'index').map(&:first)]
      end
    rescue StandardError => e
      Rails.logger.warn("reports form: #{e.class}: #{e.message}")
      @values = Hash.new([])
      flash.now[:alert] = flash_text('index_down')
    end

    def show
      kind = params[:kind].to_s
      return redirect_to(admin_etd_reports_path, alert: flash_text('unknown_report')) unless KINDS.include?(kind)

      p = params.permit(*PERMITTED).to_h
      preview = request.format.html?
      @report = build(kind, p, preview)
      audit('report', kind, "#{request.format.symbol} #{p.compact_blank.to_query}".truncate(900))
      respond_to do |format|
        format.html
        format.xlsx do
          send_data ReportXlsx.render(@report), filename: @report.filename('xlsx'),
                                                type: Mime[:xlsx].to_s, disposition: 'attachment'
        end
        format.pdf do
          send_data ReportPdf.render(@report), filename: @report.filename('pdf'), type: 'application/pdf',
                                               disposition: 'attachment'
        end
      end
    rescue RSolr::Error::Http, Errno::ECONNREFUSED, Faraday::Error => e
      Rails.logger.warn("report #{kind}: #{e.class}: #{e.message}")
      redirect_to admin_etd_reports_path, alert: flash_text('report_down')
    end

    private

    def build(kind, p, preview)
      case kind
      when 'institution' then HeaReport.institution(p, usage: p['usage'] == '1')
      when 'supervisors' then HeaReport.supervisors(p, list: !preview && p['list'] != '0')
      else HeaReport.custom(p, list_max: preview ? PREVIEW_ROWS : HeaReport::LIST_MAX)
      end
    end
  end
end
