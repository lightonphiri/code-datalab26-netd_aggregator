# frozen_string_literal: true

# A signed-in admin browser session (FR-36). Expires after IDLE of inactivity or LIFETIME in total.
class Session < ApplicationRecord
  IDLE = 2.hours
  LIFETIME = 12.hours
  belongs_to :user

  def expired? = updated_at < IDLE.ago || created_at < LIFETIME.ago
end
