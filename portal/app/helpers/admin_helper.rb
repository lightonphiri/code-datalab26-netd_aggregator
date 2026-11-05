# frozen_string_literal: true

module AdminHelper
  # "November 1, 2026, 02:30" in the installation's time zone (config/country.yml); accepts a Time or epoch seconds (harvest_runs).
  def admin_time(t)
    return '—' if t.blank?

    t = Time.at(t.to_f) if t.is_a?(Numeric)
    l(t.in_time_zone(Netd.time_zone), format: :netd)
  end

  def run_badge(status)
    cls = { 'ok' => 'success', 'error' => 'danger' }.fetch(status.to_s, 'secondary')
    tag.span(status.presence || nt('admin.never_run'), class: "badge text-bg-#{cls}")
  end
end
