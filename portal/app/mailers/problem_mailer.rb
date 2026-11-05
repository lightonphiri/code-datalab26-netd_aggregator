# frozen_string_literal: true

class ProblemMailer < ApplicationMailer
  RECIPIENTS = Netd.reports_to

  def report(problem_report)
    @r = problem_report
    mail(to: RECIPIENTS,
         from: ENV.fetch('SMTP_FROM', ENV.fetch('SMTP_USER', Netd.mail_sender)),
         reply_to: @r.email,
         subject: I18n.t('netd.mail.problem.subject', portal: Netd.portal_name, problem: @r.problem,
                                                             title: @r.record_title.to_s.truncate(100)))
  end
end
