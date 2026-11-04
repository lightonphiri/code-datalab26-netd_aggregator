# frozen_string_literal: true

# Result card / record page for an ETD: InvenioRDM-style badges above the title and
# an abstract snippet (results) or a link to the original repository (record page).
class EtdResultComponent < Blacklight::DocumentComponent
  include ActionView::Helpers::TextHelper

  def before_render
    # On the record page Blacklight fills the footer slot itself, so the links go in the header.
    with_header_content(safe_join([badges, source_link])) if @show && !header?
    with_footer_content(result_details) unless @show || footer?
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

  # Result line as on Academic Commons: authors; YEAR · DEGREE · INSTITUTION; subject links; PDF link.
  def result_details
    authors = Array(@document['author_ssim'])
    kicker = [first('year_ssim'), (first('degree_ssim') || first('degree_level_ssim')), first('institution_ssim')].compact
    subjects = Array(@document['subject_ssim']).first(8)
    parts = []
    parts << content_tag(:div, authors.join('; '), class: 'etd-authors') if authors.any?
    parts << content_tag(:div, safe_join(kicker.map { |k| content_tag(:span, k) }, content_tag(:span, '·', class: 'etd-dot')),
                         class: 'etd-kicker') if kicker.any?
    parts << snippet
    if subjects.any?
      parts << content_tag(:div, safe_join(subjects.map { |s| link_to(s, helpers.search_action_path(f: { subject_ssim: [s] })) }),
                           class: 'etd-subjects')
    elsif (fos = fields_of_study).any?
      # No keywords from the repository: the portal's field of study (OpenAlex Topics, FR-55), marked as such.
      parts << content_tag(:div, safe_join(fos.map { |f, v| link_to(v, helpers.search_action_path(f: { f => [v] })) }),
                           class: 'etd-subjects etd-fos', title: 'Field of study assigned by the portal (OpenAlex Topics)')
    end
    parts << cited_line
    parts << pdf_link
    safe_join(parts.compact)
  end

  def fields_of_study
    subs = Array(@document['fos_subfield_ssim']).map { |v| ['fos_subfield_ssim', v] }
    subs.presence || Array(@document['fos_field_ssim']).map { |v| ['fos_field_ssim', v] }
  end

  # "Cited by 3 (OpenAlex)" linking to the record page's Cited by section (FR-69)
  def cited_line
    n = @document['cited_by_isi'].to_i
    return nil unless n.positive?

    content_tag(:div, link_to("Cited by #{n}", "#{helpers.solr_document_path(@document)}#cited-by",
                              title: 'Works citing this thesis, from OpenAlex'), class: 'etd-cited')
  end

  def pdf_link(css = 'etd-pdf-link')
    url = first('pdf_url_ssm')
    return nil unless url

    link_to('Download PDF ↓', helpers.record_pdf_path(@document), class: css, target: '_blank', rel: 'noopener nofollow')
  end

  def snippet
    text = first('abstract_tesim')
    text ? content_tag(:p, truncate(text.squish, length: 300, separator: ' '), class: 'etd-snippet') : nil
  end

  def source_link
    url = first('url_ssm')
    links = [pdf_link('btn btn-primary btn-sm me-2'),
             (link_to('View in the institutional repository ↗', url, class: 'btn btn-outline-primary btn-sm',
                                                                     target: '_blank', rel: 'noopener') if url)].compact
    links.empty? ? '' : content_tag(:p, safe_join(links), class: 'etd-source')
  end
end
