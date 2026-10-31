# frozen_string_literal: true

class ProblemMailer < ApplicationMailer
  RECIPIENTS = %w[lighton.phiri@unza.ac.zm datalab@unza.zm].freeze

  def report(problem_report)
    @r = problem_report
    mail(to: RECIPIENTS,
         from: ENV.fetch('SMTP_FROM', ENV.fetch('SMTP_USER', 'lighton.phiri@unza.ac.zm')),
         reply_to: @r.email,
         subject: "(Zambia National ETD Portal) #{@r.problem}: #{@r.record_title.to_s.truncate(100)}")
  end
end
