# frozen_string_literal: true

# Atom entry (overrides Blacklight's, which stamps every entry with the current time): <updated> is when the record
# first appeared in the portal, so feed readers show only genuinely new theses as new (FR-60).
presenter = document_presenter(document)
url = polymorphic_url(search_state.url_for_document(document))
xml.entry do
  xml.title presenter.heading
  xml.updated(document['added_dtsi'] || document['updated_dtsi'] || Time.current.iso8601)
  xml.published(document['added_dtsi']) if document['added_dtsi']
  xml.link 'rel' => 'alternate', 'type' => 'text/html', 'href' => url
  xml.id url
  Array(document['author_ssim']).each { |a| xml.author { xml.name a } }
  summary = [document['institution_ssim']&.first, document['degree_level_ssim']&.first, document['year_isi']].compact.join(' · ')
  abstract = Array(document['abstract_tesim']).first.to_s.truncate(600)
  xml.summary [summary, abstract].reject(&:blank?).join(' — ')
end
