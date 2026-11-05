# frozen_string_literal: true

# Helpers for the record page (layout modelled on Columbia's Academic Commons).
module RecordHelper
  def rec_values(doc, field) = Array(doc[field]).reject(&:blank?)

  def rec_files(doc)
    rec_values(doc, 'files_ssm').filter_map { |j| JSON.parse(j) rescue nil }
  end

  # Values filled automatically by a metadata-filling model (SRS FR-50): { 'degree_level' => {'method'=>..., 'confidence'=>...} }
  def rec_derived(doc)
    rec_values(doc, 'derived_ssm').filter_map { |j| JSON.parse(j) rescue nil }.to_h { |h| [h['field'], h] }
  end

  def derived_badge(derived, solr_field)
    info = derived[solr_field.sub(/_(ssim|tsim|ssm)\z/, '')]
    return ''.html_safe unless info

    tip = nt('record.derived_tip', method: info['method'].delete_prefix('model:'), confidence: format('%.2f', info['confidence'].to_f))
    tag.span(nt('record.derived'), class: 'netd-derived', title: tip, tabindex: 0, 'aria-label': tip)
  end

  def facet_link(label, field, value)
    link_to label, search_action_path(f: { field => [value] })
  end

  def human_size(bytes)
    bytes.to_i.positive? ? number_to_human_size(bytes.to_i, precision: 3) : nil
  end

  def file_label(file, index)
    name = file['name'].presence
    name || (file['mime'].to_s.include?('pdf') ? nt('record.file_pdf', n: index + 1) : nt('record.file', n: index + 1))
  end

  # "How to cite" (FR-65): the rendered entry, sanitised (only the style's own markup is kept).
  def citation_html(citation, style)
    sanitize(citation.render(style), tags: %w[i b em strong span div sup sub], attributes: %w[class])
  end
end
