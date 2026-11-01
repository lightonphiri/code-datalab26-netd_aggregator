# frozen_string_literal: true

# Stacked bar of the four origins of a value (FR-28); colours in netd.css (validated ordinal ramp).
module QualityHelper
  def quality_bar(element, label, compact: true)
    groups = QualityReport::GROUPS
    aria = groups.map { |g, (l, _)| "#{l} #{element[g]}%" }.join(', ')
    tag.span(class: ['netd-qbar', ('netd-qbar-sm' if compact)], role: 'img', 'aria-label': "#{label}: #{aria}") do
      safe_join(groups.filter_map do |g, (l, _)|
        next unless element[g].to_f.positive?

        tag.span(class: "netd-qseg netd-q-#{g}", style: "flex-basis: #{element[g]}%", title: "#{label}: #{l} #{element[g]}%")
      end)
    end
  end

  def quality_totals(inst)
    QualityReport::GROUPS.keys.to_h { |g| [g, (inst['elements'].sum { |e| e[g] } / inst['elements'].size).round(1)] }
  end
end
