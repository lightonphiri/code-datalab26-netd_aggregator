class ApplicationMailer < ActionMailer::Base
  default from: Netd.mail_from
  layout false
end
