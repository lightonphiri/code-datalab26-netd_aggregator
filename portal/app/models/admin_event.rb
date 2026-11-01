# frozen_string_literal: true

# Audit log of admin panel actions (FR-41): who did what, to which subject, from where.
class AdminEvent < ApplicationRecord
  belongs_to :user, optional: true

  def self.record(action, subject = nil, detail = nil, user: Current.user, ip: nil)
    create!(action: action, subject: subject, detail: detail&.to_s&.truncate(4000), user: user, ip_address: ip)
  end
end
