# frozen_string_literal: true

# Receives the "Report a problem" form from record pages, stores it and emails it.
class ProblemReportsController < ApplicationController
  rate_limit to: 5, within: 10.minutes, only: :create,
             with: -> { redirect_back fallback_location: root_path, alert: 'Too many reports from your connection; please try again later.' }

  def create
    return redirect_back(fallback_location: root_path) if params[:website].present? # spam trap

    report = ProblemReport.new(params.require(:problem_report)
                                     .permit(:problem, :message, :name, :email, :record_url, :record_title)
                                     .merge(remote_ip: request.remote_ip))
    if report.save
      begin
        ProblemMailer.report(report).deliver_now
        report.update(emailed: true)
      rescue StandardError => e
        report.update(email_error: e.message.truncate(500))
        Rails.logger.error("Problem report #{report.id} not emailed: #{e.message}")
      end
      redirect_back fallback_location: root_path, notice: 'Thank you. Your report has been sent to the portal team.'
    else
      redirect_back fallback_location: root_path, alert: "Your report could not be sent: #{report.errors.full_messages.to_sentence}."
    end
  end
end
