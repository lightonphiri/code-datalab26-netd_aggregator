# frozen_string_literal: true

module Admin
  # Base for every admin page: signed-in users only, no caching, not indexed, password change enforced.
  class BaseController < ApplicationController
    include Blacklight::Configurable
    include AdminAuthentication
    copy_blacklight_config_from(CatalogController)
    layout 'blacklight'
    before_action :no_store, :require_password_change

    private

    def no_store
      response.headers['Cache-Control'] = 'no-store'
      response.headers['X-Robots-Tag'] = 'noindex, nofollow'
    end

    def require_password_change
      redirect_to edit_admin_password_path if current_admin&.must_change_password? && controller_name != 'passwords'
    end
  end
end
