# frozen_string_literal: true

require 'caxlsx'

# Excel rendering of a HeaReport (SRS FR-63): a Summary sheet (title, filters, contents, notes, summary figures) and
# one styled sheet per section, with filters, frozen header, data bars on counts and a native chart where useful.
module ReportXlsx
  NAVY = '1F4E79'
  BLUE = '2E75B6'
  PALE = 'DDEBF7'
  ZEBRA = 'F3F8FC'
  SERIES = %w[1F4E79 2E75B6 9DC3E6 BFBFBF].freeze  # Doctoral, Masters, PG Diploma, Not recorded
  LINK_MAX = 5_000  # clickable links per sheet (Excel allows about 65,000)

  module_function

  def render(report)
    pkg = Axlsx::Package.new
    pkg.use_shared_strings = true
    wb = pkg.workbook
    st = styles(wb)
    names = sheet_names(report)
    summary_sheet(wb, st, report, names)
    report.sections.each_with_index do |sec, i|
      next if i.zero? && sec.kind == :summary

      section_sheet(wb, st, sec, names[i])
    end
    pkg.core.creator = "#{Netd.portal_name} (#{Netd.host})"
    pkg.to_stream.read
  end

  def styles(wb)
    s = wb.styles
    base = { sz: 10, font_name: 'Calibri' }
    {
      title: s.add_style(b: true, sz: 18, fg_color: NAVY, font_name: 'Calibri'),
      subtitle: s.add_style(sz: 12, fg_color: BLUE, font_name: 'Calibri'),
      small: s.add_style(sz: 9, fg_color: '595959', i: true, font_name: 'Calibri', alignment: { wrap_text: false }),
      h2: s.add_style(b: true, sz: 13, fg_color: NAVY, font_name: 'Calibri'),
      head: s.add_style(base.merge(b: true, fg_color: 'FFFFFF', bg_color: NAVY, alignment: { vertical: :center, wrap_text: true },
                                   border: { style: :thin, color: 'FFFFFF' })),
      key: s.add_style(base.merge(b: true, bg_color: PALE)),
      text: s.add_style(base.merge(alignment: { vertical: :top })),
      wrap: s.add_style(base.merge(alignment: { vertical: :top, wrap_text: true })),
      num: s.add_style(base.merge(num_fmt: 3, alignment: { vertical: :top })),
      year: s.add_style(base.merge(num_fmt: 1, alignment: { vertical: :top, horizontal: :left })),
      pct: s.add_style(base.merge(format_code: '0.0', alignment: { vertical: :top })),
      link: s.add_style(base.merge(fg_color: '0563C1', u: true, alignment: { vertical: :top })),
      total: s.add_style(base.merge(b: true, bg_color: PALE, border: { style: :thin, color: NAVY, edges: [:top] })),
      total_num: s.add_style(base.merge(b: true, num_fmt: 3, bg_color: PALE, border: { style: :thin, color: NAVY, edges: [:top] }))
    }
  end

  def sheet_names(report)
    used = {}
    report.sections.map do |sec|
      base = sec.title.gsub(%r{[\[\]:*?/\\']}, ' ').squeeze(' ').strip.first(28)
      name = base
      n = 1
      name = "#{base.first(25)} #{n += 1}" while used[name.downcase]
      used[name.downcase] = true
      name
    end
  end

  def summary_sheet(wb, st, report, names)
    wb.add_worksheet(name: report.sections.first&.kind == :summary ? names.first : 'Summary') do |ws|
      ws.add_row [report.title], style: st[:title], height: 28
      ws.add_row [report.subtitle], style: st[:subtitle]
      ws.add_row ["#{Netd.portal_name} (#{Netd.host}) · generated #{HeaReport.date(report.generated_at)}, " \
                  "#{report.generated_at.strftime('%H:%M')} UTC"], style: st[:small]
      ws.add_row []
      ws.add_row ['Filters'], style: st[:h2]
      report.filters.each { |k, v| ws.add_row [k, v], style: [st[:key], st[:text]], types: %i[string string] }
      ws.add_row []
      first = report.sections.first
      if first&.kind == :summary
        ws.add_row [first.title], style: st[:h2]
        table(ws, st, first, links: false)
        ws.add_row []
      end
      others = report.sections.each_with_index.reject { |s, i| i.zero? && s.kind == :summary }
      if others.any?
        ws.add_row ['Contents'], style: st[:h2]
        others.each do |sec, i|
          ws.add_row [sec.title, "#{sec.rows.size} rows"], style: [st[:link], st[:small]]
          ws.add_hyperlink(location: "'#{names[i]}'!A1", target: :sheet, ref: "A#{ws.rows.size}")
        end
        ws.add_row []
      end
      ws.add_row ['Notes'], style: st[:h2]
      report.notes.each { |n| ws.add_row [n], style: st[:text] }
      ws.column_widths 52, 30, 16
    end
  end

  def section_sheet(wb, st, sec, name)
    wb.add_worksheet(name: name) do |ws|
      ws.add_row [sec.title], style: st[:title], height: 26
      ws.add_row [sec.note.to_s], style: st[:small] if sec.note.present?
      ws.add_row []
      top, bottom = table(ws, st, sec, links: sec.rows.size <= LINK_MAX)
      ncol = sec.headers.size
      last = col(ncol - 1)
      ws.auto_filter = "A#{top}:#{last}#{bottom}" if bottom > top
      ws.sheet_view.pane do |p|
        p.top_left_cell = "A#{top + 1}"
        p.state = :frozen
        p.y_split = top
      end
      widths(ws, sec)
      data_bars(ws, sec, top, bottom)
      chart(ws, sec, top, bottom, ncol) if sec.chart && sec.rows.any?
    end
  end

  # Writes header, rows and optional total; returns [header row, last data row].
  def table(ws, st, sec, links:)
    ws.add_row sec.headers, style: st[:head], height: 30
    top = ws.rows.size
    link_cols = sec.headers.each_index.select { |i| sec.headers[i].to_s.end_with?('link', 'Link') }
    wrap_cols = sec.headers.each_index.select { |i| %w[Title Abstract].include?(sec.headers[i]) }
    sec.rows.each do |row|
      styles = row.each_with_index.map do |v, i|
        if link_cols.include?(i) then st[:link]
        elsif sec.headers[i].to_s.start_with?('%') then st[:pct]
        elsif sec.headers[i].to_s.match?(/year/i) then st[:year]
        elsif v.is_a?(Numeric) then st[:num]
        elsif wrap_cols.include?(i) then st[:wrap]
        else st[:text]
        end
      end
      ws.add_row row, style: styles, types: row.map { |v| v.is_a?(Numeric) ? nil : :string }
      link_cols.each do |i|
        url = row[i].to_s
        ws.add_hyperlink(location: url, ref: "#{col(i)}#{ws.rows.size}") if links && url.start_with?('http')
      end
    end
    bottom = ws.rows.size
    if sec.total && sec.rows.any?
      tot = sec.headers.each_with_index.map do |h, i|
        next 'Total' if i.zero?
        next nil unless sec.rows.all? { |r| r[i].nil? || r[i].is_a?(Integer) } && !h.to_s.match?(/year/i)

        sec.rows.sum { |r| r[i].to_i }
      end
      ws.add_row tot, style: tot.each_index.map { |i| i.zero? ? st[:total] : st[:total_num] }
    end
    [top, bottom]
  end

  def widths(ws, sec)
    w = sec.headers.each_with_index.map do |h, i|
      longest = ([h.to_s.size] + sec.rows.first(500).map { |r| r[i].to_s.size }).max
      cap = %w[Title Abstract].include?(h) ? 70 : 48
      [[longest + 2, 9].max, cap].min
    end
    ws.column_widths(*w)
  end

  # data bars on the main count column of count tables
  def data_bars(ws, sec, top, bottom)
    return if %i[listing summary].include?(sec.kind) || bottom <= top

    i = sec.headers.index('Theses') || sec.headers.index('Total') || (sec.kind == :usage ? 1 : nil)
    return unless i && sec.rows.first[i].is_a?(Numeric)

    ws.add_conditional_formatting("#{col(i)}#{top + 1}:#{col(i)}#{bottom}",
                                  type: :dataBar, priority: 1, data_bar: Axlsx::DataBar.new(color: 'FF5B9BD5'))
  end

  def chart(ws, sec, top, bottom, ncol)
    n = sec.chart == :bar_top ? [bottom - top, 20].min : bottom - top
    return if n < 1 || (n > 60 && sec.chart != :column)

    last = top + n
    cat = "A#{top + 1}:A#{last}"
    anchor = ncol + 1
    height = sec.chart == :column || sec.chart == :stacked ? 22 : [n + 4, 14].max
    title = sec.chart == :bar_top ? "#{sec.title}: top #{n}" : sec.title
    opts = { start_at: [anchor, top - 1], end_at: [anchor + (n > 20 && %i[column stacked].include?(sec.chart) ? 18 : 12), top - 1 + height], title: title,
             bar_dir: %i[column stacked].include?(sec.chart) ? :col : :bar }
    opts[:grouping] = :stacked if sec.chart == :stacked
    ws.add_chart(Axlsx::BarChart, **opts) do |c|
      c.overlap = 100 if sec.chart == :stacked
      c.gap_width = 60
      if sec.chart == :stacked
        (1..(sec.headers.size - 2)).each do |j|
          c.add_series data: ws["#{col(j)}#{top + 1}:#{col(j)}#{last}"], labels: ws[cat], title: sec.headers[j],
                       series_color: SERIES[j - 1] || BLUE
        end
      else
        c.add_series data: ws["B#{top + 1}:B#{last}"], labels: ws[cat], title: sec.headers[1], series_color: BLUE
        c.show_legend = false
      end
      c.cat_axis.scaling.orientation = :maxMin if opts[:bar_dir] == :bar
      c.cat_axis.label_rotation = -45 if opts[:bar_dir] == :col && n > 12
      c.val_axis.gridlines = true
    end
  end

  def col(i)
    s = +''
    i += 1
    while i.positive?
      i, r = (i - 1).divmod(26)
      s.prepend((65 + r).chr)
    end
    s
  end
end
