class ApplicationController < ActionController::Base
  # Adds a few additional behaviors into the application controller
  include Blacklight::Controller
  layout :determine_layout if respond_to? :layout

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

  # A flash message from portal/config/locales/en.yml under netd.flash, with the country values (packaging P4g)
  def flash_text(key, **values) = I18n.t("netd.flash.#{key}", **Netd.text_values.merge(values))
end
