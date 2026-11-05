# frozen_string_literal: true

require 'csv'

# The metadata quality report written by `netd.cli quality-report` after every scheduled run (SRS FR-28).
# Public page: overall figures only; per-institution breakdown in the admin panel.
class QualityReport
  # code => [label, description]; text in en.yml under netd.quality_groups (P4e)
  GROUPS = LocalisedLabels.new('netd.quality_groups', %w[repository elsewhere portal missing], fields: %w[label description])

  def self.load
    JSON.parse(File.read(File.join(Harvester::LOGS, 'quality.json')))
  rescue Errno::ENOENT, JSON::ParserError
    nil
  end

  # Overall figures only (no institution names), for the public page and downloads.
  def self.public(report)
    return nil unless report

    all = report['institutions'].find { |i| i['id'].nil? }
    report.merge('institutions' => [all].compact.map { |i| i.except('to_improve') },
                 'institutions_measured' => report['institutions'].count { |i| i['id'] })
  end

  def self.to_csv(report)
    CSV.generate do |csv|
      csv << %w[institution records element etd_ms_element in_repository_element_pct elsewhere_in_repository_pct
                filled_by_portal_pct missing_pct]
      (report&.dig('institutions') || []).each do |i|
        i['elements'].each do |e|
          csv << [i['name'], i['records'], e['label'], e['etdms'], e['repository'], e['elsewhere'], e['portal'], e['missing']]
        end
      end
    end
  end
end
