# frozen_string_literal: true

module Admin
  class SessionsController < BaseController
    skip_before_action :require_admin, only: %i[new create]
    skip_before_action :require_password_change
    rate_limit to: 10, within: 3.minutes, only: :create,
               with: -> { redirect_to admin_sign_in_path, alert: 'Too many attempts. Wait a few minutes and try again.' }

    def new
      redirect_to admin_root_path if resume_session
    end

    def create
      user = User.find_by(email_address: params[:email_address].to_s.strip.downcase, active: true)
      if user&.authenticate(params[:password].to_s)
        start_session(user)
        audit('sign_in')
        redirect_to(session.delete(:admin_return_to) || admin_root_path)
      else
        AdminEvent.record('sign_in_failed', params[:email_address].to_s.truncate(200), nil, user: nil, ip: request.remote_ip)
        redirect_to admin_sign_in_path, alert: 'Email address or password not recognised.'
      end
    end

    def destroy
      audit('sign_out')
      end_session
      redirect_to admin_sign_in_path, notice: 'Signed out.'
    end
  end
end
