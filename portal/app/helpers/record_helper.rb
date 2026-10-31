# frozen_string_literal: true

# Helpers for the record page (layout modelled on Columbia's Academic Commons).
module RecordHelper
  def rec_values(doc, field) = Array(doc[field]).reject(&:blank?)

  def rec_files(doc)
    rec_values(doc, 'files_ssm').filter_map { |j| JSON.parse(j) rescue nil }
  end

  def facet_link(label, field, value)
    link_to label, search_action_path(f: { field => [value] })
  end

  def human_size(bytes)
    bytes.to_i.positive? ? number_to_human_size(bytes.to_i, precision: 3) : nil
  end

  def file_label(file, index)
    name = file['name'].presence
    name || (file['mime'].to_s.include?('pdf') ? "Full text (PDF) #{index + 1}" : "File #{index + 1}")
  end
end
