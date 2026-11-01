# frozen_string_literal: true

# RSS item with a date (when the record first appeared in the portal) and a stable guid (FR-60).
url = polymorphic_url(search_state.url_for_document(document))
xml.item do
  xml.title(document_presenter(document).heading)
  xml.link(url)
  xml.guid(url, 'isPermaLink' => 'true')
  xml.pubDate(Time.zone.parse(document['added_dtsi']).rfc2822) if document['added_dtsi']
  xml.author(Array(document['author_ssim']).first) if document['author_ssim'].present?
  summary = [document['institution_ssim']&.first, document['degree_level_ssim']&.first, document['year_isi']].compact.join(' · ')
  xml.description([summary, Array(document['abstract_tesim']).first.to_s.truncate(600)].reject(&:blank?).join(' — '))
end
