# frozen_string_literal: true

# Sign-in for the admin panel (FR-36), after the Rails 8 authentication generator: a database session referenced by
# a signed, HTTP-only cookie. Public pages never load this.
module AdminAuthentication
  extend ActiveSupport::Concern
  COOKIE = :netd_admin_session

  included do
    before_action :require_admin
    helper_method :current_admin
  end

  private

  def current_admin = Current.user

  def require_admin
    resume_session || request_sign_in
  end

  def resume_session
    Current.session ||= find_session
  end

  def find_session
    id = cookies.signed[COOKIE]
    session = id && Session.find_by(id: id)
    return nil unless session&.user&.active?

    if session.expired?
      session.destroy
      return nil
    end
    session.touch if session.updated_at < 1.minute.ago
    session
  end

  def request_sign_in
    session[:admin_return_to] = request.fullpath if request.get?
    redirect_to admin_sign_in_path
  end

  def start_session(user)
    user.sessions.where(updated_at: ...Session::IDLE.ago).delete_all
    s = user.sessions.create!(user_agent: request.user_agent.to_s.truncate(250), ip_address: request.remote_ip)
    user.update_column(:last_sign_in_at, Time.current)
    Current.session = s
    cookies.signed[COOKIE] = { value: s.id, httponly: true, same_site: :lax, secure: Rails.env.production?,
                               expires: Session::LIFETIME }
  end

  def end_session
    Current.session&.destroy
    cookies.delete(COOKIE)
  end

  def audit(action, subject = nil, detail = nil)
    AdminEvent.record(action, subject, detail, ip: request.remote_ip)
  end
end
