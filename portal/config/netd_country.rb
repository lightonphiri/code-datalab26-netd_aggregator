# frozen_string_literal: true

require 'yaml'
require 'tzinfo'

# The installation's country configuration (config/country.yml; SRS FR-70, SDD "Country configuration").
# Loaded once from config/application.rb, before the environment files, so that production.rb and every class can
# read it. A missing file or key stops start-up with a message naming the file and the key.
module Netd
  REQUIRED = %w[country.name country.adjective country.time_zone portal.name portal.wordmark portal.host
                regulator.name regulator.short_name regulator.url contact.email contact.reports_to mail.from
                mail.sender].freeze

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
      wordmark = dig(data, 'portal.wordmark')
      raise "NETD: #{file}: portal.wordmark must be a list of two parts" unless wordmark.is_a?(Array) && wordmark.size == 2

      bad = Array(dig(data, 'credits')).reject { |c| c.is_a?(Hash) && %w[name url role].all? { |k| !blank?(c[k]) } }
      raise "NETD: #{file}: every entry in credits needs name, url and role" if bad.any?

      deep_freeze(data)
    end

    def get(key) = dig(config, key)

    # Theme folder (packaging P5): themes/<portal.theme>/, "default" when not set; checked at start-up.
    def theme = get('portal.theme').to_s.empty? ? 'default' : get('portal.theme')
    def theme_dir = File.expand_path("../../themes/#{theme}", __dir__)

    def country_name = get('country.name')
    def country_adjective = get('country.adjective')
    def time_zone = get('country.time_zone')
    # "Lusaka" for Africa/Lusaka: the label used in "(Lusaka time)".
    def time_zone_label = time_zone.split('/').last.tr('_', ' ')
    def portal_name = get('portal.name')
    # The two parts of the header wordmark ("Zambia", "National ETD Portal").
    def wordmark = get('portal.wordmark')
    def host = get('portal.host')
    def base_url = "https://#{host}"
    def contact_email = get('contact.email')
    def reports_to = Array(get('contact.reports_to'))
    def mail_from = get('mail.from')
    def mail_sender = get('mail.sender')
    def regulator_name = get('regulator.name')
    def regulator_short_name = get('regulator.short_name')
    def regulator_url = get('regulator.url')
    def regulator_register_url = get('regulator.register_url')
    # Credits (header bar, footer, About, Credits), in the file's order; credit('developed by') and credit('hosted by').
    def credits = Array(get('credits'))
    def credit(role) = credits.find { |c| c['role'] == role }
    # Logo title and alternative text: "ZAMREN — Zambia Research and Education Network" where a full name is given.
    def credit_title(c) = c['full_name'] || c['name']
    def credit_alt(c) = c['full_name'] ? "#{c['name']} — #{c['full_name']}" : c['name']
    # Installation words kept capitalised in citations (merged with Citation::KEEP_GENERAL).
    def keep_capitals = Array(get('citation.keep_capitals'))
    # Values every interface text may use (config/locales/en.yml, keys under netd.; SRS NFR-15, SDD 8.1):
    # %{portal}, %{country}, %{country_adjective}, %{regulator}, %{regulator_short}, %{email}, %{host}, %{base_url}.
    def text_values = { portal: portal_name, country: country_name, country_adjective: country_adjective,
                        regulator: regulator_name, regulator_short: regulator_short_name, email: contact_email,
                        host: host, base_url: base_url }

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
