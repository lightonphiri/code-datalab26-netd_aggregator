# frozen_string_literal: true

require 'yaml'
require 'tzinfo'

# The installation's country configuration (config/country.yml; SRS FR-70, SDD "Country configuration").
# Loaded once from config/application.rb, before the environment files, so that production.rb and every class can
# read it. A missing file or key stops start-up with a message naming the file and the key.
module Netd
  REQUIRED = %w[country.name country.adjective country.time_zone portal.name portal.host contact.email
                contact.reports_to mail.from mail.sender].freeze

  class << self
    def path = ENV['NETD_COUNTRY'].to_s.empty? ? File.expand_path('../../config/country.yml', __dir__) : ENV['NETD_COUNTRY']

    def config = @config ||= load_config

    def load_config(file = path)
      raise "NETD: country configuration not found at #{file} (copy one from config/examples/; manual chapter 7)" unless File.file?(file)

      data = YAML.safe_load_file(file) || {}
      missing = REQUIRED.select { |k| blank?(dig(data, k)) }
      raise "NETD: #{file} lacks #{missing.join(', ')}" if missing.any?

      begin
        TZInfo::Timezone.get(dig(data, 'country.time_zone'))
      rescue TZInfo::InvalidTimezoneIdentifier
        raise "NETD: #{file}: country.time_zone #{dig(data, 'country.time_zone').inspect} is not an IANA time zone name"
      end
      deep_freeze(data)
    end

    def get(key) = dig(config, key)

    def country_name = get('country.name')
    def country_adjective = get('country.adjective')
    def time_zone = get('country.time_zone')
    # "Lusaka" for Africa/Lusaka: the label used in "(Lusaka time)".
    def time_zone_label = time_zone.split('/').last.tr('_', ' ')
    def portal_name = get('portal.name')
    def host = get('portal.host')
    def base_url = "https://#{host}"
    def contact_email = get('contact.email')
    def reports_to = Array(get('contact.reports_to'))
    def mail_from = get('mail.from')
    def mail_sender = get('mail.sender')

    private

    def dig(data, key) = key.split('.').reduce(data) { |h, part| h.is_a?(Hash) ? h[part] : nil }
    def blank?(value) = value.nil? || (value.respond_to?(:empty?) && value.empty?)

    def deep_freeze(obj)
      case obj
      when Hash then obj.each_value { |v| deep_freeze(v) }
      when Array then obj.each { |v| deep_freeze(v) }
      end
      obj.freeze
    end
  end
end
