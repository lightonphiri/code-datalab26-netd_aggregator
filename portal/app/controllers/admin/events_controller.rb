# frozen_string_literal: true

module Admin
  # Audit log (FR-41).
  class EventsController < BaseController
    def index
      @events = AdminEvent.includes(:user).order(created_at: :desc).limit(500)
    end
  end
end
