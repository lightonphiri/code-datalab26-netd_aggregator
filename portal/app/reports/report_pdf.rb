# frozen_string_literal: true

require 'prawn'
require 'prawn/table'

# PDF rendering of a HeaReport (SRS FR-63): A4, title band, filters and notes, a bar chart for count tables, styled
# tables (repeated header, alternate row shading), long listings in landscape, page numbers and source in the footer.
module ReportPdf
  NAVY = '1F4E79'
  BLUE = '2E75B6'
  PALE = 'DDEBF7'
  ZEBRA = 'F3F8FC'
  SERIES = %w[1F4E79 2E75B6 9DC3E6 BFBFBF].freeze
  FONT_DIR = '/usr/share/fonts/truetype/dejavu'
  ROW_MAX = 1_500  # rows per table in the PDF; the Excel file has them all
  CHART_MAX = 25

  module_function

  def render(report)
    pdf = Prawn::Document.new(page_size: 'A4', margin: [56, 40, 48, 40], info: { Title: report.title,
                                                                              Creator: 'Zambia National ETD Portal (netd.ac.zm)' })
    fonts(pdf)
    title_band(pdf, report)
    filters(pdf, report)
    report.sections.each { |sec| section(pdf, sec) }
    notes(pdf, report)
    footer(pdf, report)
    pdf.render
  end

  def fonts(pdf)
    return unless File.exist?("#{FONT_DIR}/DejaVuSans.ttf")

    pdf.font_families.update('DejaVu' => { normal: "#{FONT_DIR}/DejaVuSans.ttf", bold: "#{FONT_DIR}/DejaVuSans-Bold.ttf",
                                           italic: "#{FONT_DIR}/DejaVuSans-Oblique.ttf",
                                           bold_italic: "#{FONT_DIR}/DejaVuSans-BoldOblique.ttf" })
    pdf.font('DejaVu')
  end

  # Helvetica (fallback) only has Windows-1252 characters
  def safe(pdf, s)
    s = s.to_s
    return s if pdf.font.family == 'DejaVu'

    s.encode('Windows-1252', invalid: :replace, undef: :replace, replace: '?').encode('UTF-8')
  end

  def title_band(pdf, report)
    pdf.fill_color NAVY
    pdf.fill_rectangle [-40, pdf.bounds.top + 56], pdf.bounds.width + 80, 110
    pdf.fill_color 'FFFFFF'
    pdf.text_box 'ZAMBIA NATIONAL ETD PORTAL', at: [0, pdf.bounds.top + 40], size: 9, character_spacing: 1.5
    pdf.text_box safe(pdf, report.title), at: [0, pdf.bounds.top + 24], size: 20, style: :bold,
                                         width: pdf.bounds.width, height: 26, overflow: :shrink_to_fit
    pdf.text_box safe(pdf, report.subtitle), at: [0, pdf.bounds.top - 6], size: 11, width: pdf.bounds.width
    pdf.text_box "Generated #{HeaReport.date(report.generated_at)}, #{report.generated_at.strftime('%H:%M')} UTC · netd.ac.zm",
                 at: [0, pdf.bounds.top - 24], size: 8.5, color: 'DDEBF7'
    pdf.fill_color '000000'
    pdf.move_down 70
  end

  def filters(pdf, report)
    rows = report.filters.map { |k, v| [k, safe(pdf, v)] }
    pdf.table(rows, cell_style: { size: 9, borders: [], padding: [2, 8, 2, 0] }, column_widths: [150]) do |t|
      t.column(0).font_style = :bold
      t.column(0).text_color = NAVY
    end
    pdf.move_down 12
  end

  def heading(pdf, text)
    pdf.start_new_page if pdf.cursor < 120
    pdf.fill_color NAVY
    pdf.text safe(pdf, text), size: 13, style: :bold
    pdf.fill_color '000000'
    pdf.stroke_color BLUE
    pdf.line_width 1.2
    pdf.stroke_horizontal_line 0, pdf.bounds.width
    pdf.move_down 6
  end

  def section(pdf, sec)
    want = (sec.headers.size > 6 || sec.kind == :listing) && sec.rows.any? ? :landscape : :portrait
    pdf.start_new_page(layout: want) if pdf.page.layout != want
    heading(pdf, sec.title)
    if sec.note.present?
      pdf.text safe(pdf, sec.note), size: 8.5, color: '595959', style: :italic
      pdf.move_down 6
    end
    if sec.rows.empty?
      pdf.text 'None.', size: 9
      pdf.move_down 10
      return
    end
    bar_chart(pdf, sec) if %i[bar bar_top column].include?(sec.chart)
    stacked_chart(pdf, sec) if sec.chart == :stacked
    table(pdf, sec)
    pdf.move_down 14
  end

  def fmt(v, plain = false)
    case v
    when Integer then plain ? v.to_s : v.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
    when Float then format('%.1f', v)
    else v.to_s
    end
  end

  def table(pdf, sec)
    rows = sec.rows.first(ROW_MAX)
    years = sec.headers.map { |h| h.to_s.match?(/year/i) }
    data = [sec.headers.map { |h| safe(pdf, h) }] + rows.map { |r| r.each_with_index.map { |v, i| safe(pdf, fmt(v, years[i])) } }
    numeric = sec.headers.each_index.select { |i| rows.all? { |r| r[i].nil? || r[i].is_a?(Numeric) } }
    if sec.total
      data << sec.headers.each_with_index.map do |h, i|
        next 'Total' if i.zero?
        next '' unless numeric.include?(i) && rows.all? { |r| r[i].nil? || r[i].is_a?(Integer) } && !h.match?(/year|%/i)

        fmt(sec.rows.sum { |r| r[i].to_i })
      end
    end
    size = sec.kind == :listing ? 7 : 8.5
    opts = { header: true }
    opts[:width] = pdf.bounds.width if sec.headers.size > 3
    opts[:column_widths] = listing_widths(pdf, sec.headers) if sec.kind == :listing
    pdf.table(data, **opts, cell_style: { size: size, padding: [3, 4], border_width: 0.4, border_color: 'BFBFBF',
                                  overflow: :shrink_to_fit, inline_format: false }) do |t|
      t.row(0).background_color = NAVY
      t.row(0).text_color = 'FFFFFF'
      t.row(0).font_style = :bold
      (1...data.size).each { |i| t.row(i).background_color = ZEBRA if i.even? }
      numeric.each { |i| t.column(i).align = :right }
      if sec.total
        t.row(-1).font_style = :bold
        t.row(-1).background_color = PALE
      end
    end
    return if sec.rows.size <= ROW_MAX

    pdf.move_down 4
    pdf.text "First #{fmt(ROW_MAX)} of #{fmt(sec.rows.size)} rows; the Excel version has them all.", size: 8.5, style: :italic
  end

  WEIGHTS = { 'Title' => 3.0, 'Abstract' => 4.0, 'Portal link' => 1.8, 'Repository link' => 1.8, 'Year' => 0.45,
              'Keywords' => 1.6, 'Fields of study' => 1.4, 'Department' => 1.4, 'Supervisor' => 1.2,
              'Supervisor(s)' => 1.3, 'Author(s)' => 1.2, 'Full text' => 0.6, 'Filled by the portal' => 1.3 }.freeze

  def listing_widths(pdf, headers)
    w = headers.map { |h| WEIGHTS.fetch(h, 1.0) }
    headers.each_index.to_h { |i| [i, pdf.bounds.width * w[i] / w.sum] }
  end

  # horizontal bars: label, bar, value (top rows only)
  def bar_chart(pdf, sec)
    rows = sec.rows.select { |r| r[1].is_a?(Numeric) }.first(sec.chart == :column ? 60 : CHART_MAX)
    return if rows.size < 2

    rows = rows.first(CHART_MAX) unless sec.chart == :column
    return column_chart(pdf, rows) if sec.chart == :column

    peak = [rows.map { |r| r[1] }.max.to_f, 1].max
    label_w = 170
    bar_w = pdf.bounds.width - label_w - 50
    h = 11
    pdf.start_new_page if pdf.cursor < rows.size * h + 20
    top = pdf.cursor
    rows.each_with_index do |r, i|
      y = top - i * h
      pdf.fill_color '262626'
      pdf.text_box safe(pdf, r[0]), at: [0, y], width: label_w - 6, height: h, size: 7.5, overflow: :shrink_to_fit,
                                   align: :right, valign: :center, single_line: true
      w = [bar_w * r[1] / peak, 0.5].max
      pdf.fill_color BLUE
      pdf.fill_rectangle [label_w, y - 1.5], w, h - 3
      pdf.fill_color '262626'
      pdf.text_box fmt(r[1]), at: [label_w + w + 3, y], width: 45, height: h, size: 7, valign: :center
    end
    pdf.fill_color '000000'
    pdf.move_cursor_to top - rows.size * h - 10
  end

  def column_chart(pdf, rows)
    peak = [rows.map { |r| r[1] }.max.to_f, 1].max
    ch = 120
    pdf.start_new_page if pdf.cursor < ch + 40
    top = pdf.cursor
    slot = pdf.bounds.width / rows.size
    base = top - ch
    pdf.stroke_color 'BFBFBF'
    pdf.line_width 0.4
    pdf.stroke_horizontal_line 0, pdf.bounds.width, at: base
    step = [(rows.size / 15.0).ceil, 1].max
    rows.each_with_index do |r, i|
      bh = ch * r[1] / peak
      pdf.fill_color BLUE
      pdf.fill_rectangle [i * slot + slot * 0.15, base + bh], slot * 0.7, bh
      next unless (i % step).zero?

      pdf.fill_color '404040'
      pdf.text_box safe(pdf, r[0]), at: [i * slot - 10, base - 2], width: slot + 20, size: 6.5, align: :center
    end
    pdf.fill_color '404040'
    pdf.text_box "peak #{fmt(peak.to_i)}", at: [0, top + 2], size: 7
    pdf.fill_color '000000'
    pdf.move_cursor_to base - 16
  end

  # columns stacked by degree level (year × level section)
  def stacked_chart(pdf, sec)
    rows = sec.rows
    return if rows.size < 2

    parts = sec.headers.size - 2
    peak = [rows.map(&:last).max.to_f, 1].max
    ch = 130
    pdf.start_new_page if pdf.cursor < ch + 50
    top = pdf.cursor
    slot = pdf.bounds.width / rows.size
    base = top - ch
    step = [(rows.size / 15.0).ceil, 1].max
    rows.each_with_index do |r, i|
      y = base
      (1..parts).each do |j|
        bh = ch * r[j].to_i / peak
        next if bh <= 0

        pdf.fill_color SERIES[j - 1] || BLUE
        pdf.fill_rectangle [i * slot + slot * 0.15, y + bh], slot * 0.7, bh
        y += bh
      end
      next unless (i % step).zero?

      pdf.fill_color '404040'
      pdf.text_box safe(pdf, r[0]), at: [i * slot - 10, base - 2], width: slot + 20, size: 6.5, align: :center
    end
    x = 0
    (1..parts).each do |j|
      pdf.fill_color SERIES[j - 1] || BLUE
      pdf.fill_rectangle [x, base - 14], 8, 8
      pdf.fill_color '404040'
      pdf.text_box safe(pdf, sec.headers[j]), at: [x + 11, base - 13], size: 7.5, width: 120
      x += 125
    end
    pdf.fill_color '000000'
    pdf.move_cursor_to base - 30
  end

  def notes(pdf, report)
    return if report.notes.empty?

    heading(pdf, 'Notes')
    report.notes.each { |n| pdf.text "• #{safe(pdf, n)}", size: 8.5, leading: 2 }
  end

  def footer(pdf, report)
    pdf.repeat(:all, dynamic: true) do
      pdf.fill_color '7F7F7F'
      pdf.text_box safe(pdf, "#{report.title} · Zambia National ETD Portal, netd.ac.zm"),
                   at: [0, -20], width: pdf.bounds.width - 80, height: 12, size: 7.5
      pdf.text_box "Page #{pdf.page_number} of #{pdf.page_count}", at: [pdf.bounds.width - 80, -20], width: 80, height: 12,
                                                                    size: 7.5, align: :right
      pdf.fill_color '000000'
    end
  end
end
