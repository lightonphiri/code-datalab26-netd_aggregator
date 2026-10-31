# frozen_string_literal: true

# HEA-accredited postgraduate institutions (harvester/institutions.yml), shared by the
# home page and the Institution facet so institutions with no harvested ETDs show "0".
class InstitutionRegistry
  STATUS_LABELS = {
    'harvested' => 'Harvested',
    'no-etd-collection' => 'Repository has no ETD collection',
    'repository-unreachable' => 'Repository not reachable over OAI-PMH',
    'no-repository-known' => 'No public repository known'
  }.freeze

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
