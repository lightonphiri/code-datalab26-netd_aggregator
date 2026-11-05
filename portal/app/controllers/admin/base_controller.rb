# frozen_string_literal: true

module Admin
  # Base for every admin page: signed-in users only, no caching, not indexed, password change enforced, and
  # read-only accounts ("viewer") kept to the pages in VIEWER_PAGES.
  class BaseController < ApplicationController
    VIEWER_PAGES = %w[etd_reports quality usage passwords sessions].freeze
    include Blacklight::Configurable
    include AdminAuthentication
    copy_blacklight_config_from(CatalogController)
    layout 'blacklight'
    before_action :no_store, :require_password_change, :require_role

    private

    def no_store
      response.headers['Cache-Control'] = 'no-store'
      response.headers['X-Robots-Tag'] = 'noindex, nofollow'
    end

    def require_role
      return if current_admin.nil? || current_admin.admin? || VIEWER_PAGES.include?(controller_name)

      quiet = controller_name == 'dashboard' && action_name == 'index'   # the landing page after sign-in
      redirect_to admin_etd_reports_path,
                  alert: (quiet ? nil : flash_text('viewer_only'))
    end

    def require_password_change
      redirect_to edit_admin_password_path if current_admin&.must_change_password? && controller_name != 'passwords'
    end
  end
end
