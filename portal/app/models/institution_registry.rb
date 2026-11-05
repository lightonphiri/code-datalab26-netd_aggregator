# frozen_string_literal: true

# HEA-accredited postgraduate institutions (harvester/institutions.yml), shared by the
# home page and the Institution facet so institutions with no harvested ETDs show "0".
class InstitutionRegistry
  # Labels in en.yml under netd.institution_status (P4e)
  STATUS_LABELS = LocalisedLabels.new('netd.institution_status',
                                      %w[harvested no-etds-yet no-etd-collection repository-unreachable no-repository-known])

  def self.path
    ENV.fetch('NETD_INSTITUTIONS', Rails.root.join('..', 'harvester', 'institutions.yml').to_s)
  end

  def self.all
    @all ||= (YAML.safe_load_file(path)['institutions'] || []).map(&:symbolize_keys)
  rescue Errno::ENOENT
    []
  end

  def self.names = all.map { |i| i[:name] }
end
