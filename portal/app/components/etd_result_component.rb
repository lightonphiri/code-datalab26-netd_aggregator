# frozen_string_literal: true

# Result card / record page for an ETD: InvenioRDM-style badges above the title and
# an abstract snippet (results) or a link to the original repository (record page).
class EtdResultComponent < Blacklight::DocumentComponent
  include ActionView::Helpers::TextHelper

  def before_render
    with_header_content(badges) unless header?
    with_footer_content(@show ? source_link : safe_join([snippet, pdf_link].compact)) unless footer?
    super
  end

  private

  def first(field) = Array(@document[field]).first

  def badges
    items = [[first('degree_level_ssim'), 'level'], [first('year_ssim'), 'year'],
             [first('institution_short_ssim'), 'inst'],
             [(first('pdf_url_ssm') ? 'PDF' : nil), 'pdf']].select(&:first)
    safe_join(items.map { |text, kind| content_tag(:span, text, class: "etd-badge etd-badge-#{kind}") })
  end

  def pdf_link(css = 'etd-pdf-link')
    url = first('pdf_url_ssm')
    return nil unless url

    link_to('Download PDF ↓', url, class: css, target: '_blank', rel: 'noopener')
  end

  def snippet
    text = first('abstract_tesim')
    text ? content_tag(:p, truncate(text, length: 320, separator: ' '), class: 'etd-snippet') : ''
  end

  def source_link
    url = first('url_ssm')
    links = [pdf_link('btn btn-primary btn-sm me-2'),
             (link_to('View in the institutional repository ↗', url, class: 'btn btn-outline-primary btn-sm',
                                                                     target: '_blank', rel: 'noopener') if url)].compact
    links.empty? ? '' : content_tag(:p, safe_join(links), class: 'etd-source')
  end
end
