# frozen_string_literal: true

module AdminHelper
  # "November 1, 2026, 02:30" in Lusaka time; accepts a Time or epoch seconds (harvest_runs).
  def admin_time(t)
    return '—' if t.blank?

    t = Time.at(t.to_f) if t.is_a?(Numeric)
    t.in_time_zone('Africa/Lusaka').strftime('%B %-d, %Y, %H:%M')
  end

  def run_badge(status)
    cls = { 'ok' => 'success', 'error' => 'danger' }.fetch(status.to_s, 'secondary')
    tag.span(status.presence || 'never run', class: "badge text-bg-#{cls}")
  end
end
