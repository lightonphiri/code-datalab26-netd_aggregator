# frozen_string_literal: true

module Admin
  # Work through "Report a problem" submissions (FR-38).
  class ProblemReportsController < BaseController
    def index
      @status = ProblemReport::STATUSES.include?(params[:status]) ? params[:status] : 'open'
      @reports = ProblemReport.where(status: @status).order(created_at: @status == 'open' ? :asc : :desc).limit(200)
      @counts = ProblemReport.group(:status).count
    end

    def show
      @report = ProblemReport.find(params[:id])
    end

    def update
      @report = ProblemReport.find(params[:id])
      resolve = params[:status] == 'resolved'
      @report.update!(status: resolve ? 'resolved' : 'open', admin_note: params[:admin_note].to_s.strip.presence,
                      resolved_at: resolve ? Time.current : nil, resolved_by: resolve ? current_admin : nil)
      audit(resolve ? 'report_resolved' : 'report_reopened', "problem_report:#{@report.id}", @report.admin_note)
      redirect_to admin_problem_reports_path, notice: "Report #{@report.id} marked #{@report.status}."
    end
  end
end
