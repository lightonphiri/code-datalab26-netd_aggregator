module ApplicationHelper
  USAGE_ICONS = {
    view: '<path d="M1.5 12S5.5 5 12 5s10.5 7 10.5 7-4 7-10.5 7S1.5 12 1.5 12z"/><circle cx="12" cy="12" r="3"/>',
    download: '<path d="M12 3v12M7 10.5l5 5 5-5"/><path d="M4 17v3h16v-3"/>'
  }.freeze

  # Icons for record views (eye) and PDF downloads (arrow), FR-61; decorative, the text says what is counted.
  def usage_icon(kind, size: 16)
    tag.svg(USAGE_ICONS.fetch(kind).html_safe, width: size, height: size, viewBox: '0 0 24 24', fill: 'none',
            stroke: 'currentColor', 'stroke-width': 1.8, 'stroke-linecap': 'round', 'stroke-linejoin': 'round',
            class: 'netd-usage-icon', 'aria-hidden': true)
  end
end
