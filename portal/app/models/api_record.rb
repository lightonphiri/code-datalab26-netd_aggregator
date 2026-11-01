# frozen_string_literal: true

# Stable public representation of a record for the REST API v1 (SRS EI-6), independent of Solr field names.
module ApiRecord
  BASE = 'https://netd.ac.zm'
  FIELDS = %w[id updated_dtsi title_ssm author_ssim supervisor_ssim subject_ssim abstract_tesim year_isi degree_ssim
              degree_level_ssim discipline_ssim faculty_ssim department_ssim institution_ssim source_ssi language_ssim
              type_ssim rights_ssm url_ssm pdf_url_ssm files_ssm].join(',')
  CSV_COLUMNS = %w[id title authors supervisors year degree degree_level discipline faculty department subjects abstract
                   institution institution_id language rights portal_url source_url pdf_url updated_at].freeze

  module_function

  def list(doc, f) = Array(doc[f]).map { |v| v.to_s.strip }.reject(&:empty?).uniq
  def one(doc, f) = list(doc, f).first

  def files(doc)
    Array(doc['files_ssm']).filter_map do |j|
      f = JSON.parse(j)
      { 'url' => f['url'], 'name' => f['name'], 'mime_type' => f['mime'], 'size' => f['size'] }
    rescue JSON::ParserError
      nil
    end
  end

  def to_h(doc)
    {
      'id' => doc['id'],
      'oai_identifier' => "oai:netd.ac.zm:#{doc['id']}",
      'title' => one(doc, 'title_ssm'),
      'authors' => list(doc, 'author_ssim'),
      'supervisors' => list(doc, 'supervisor_ssim'),
      'abstract' => one(doc, 'abstract_tesim'),
      'year' => doc['year_isi'],
      'degree' => one(doc, 'degree_ssim'),
      'degree_level' => one(doc, 'degree_level_ssim'),
      'discipline' => one(doc, 'discipline_ssim'),
      'faculty' => list(doc, 'faculty_ssim'),
      'department' => list(doc, 'department_ssim'),
      'subjects' => list(doc, 'subject_ssim'),
      'language' => one(doc, 'language_ssim'),
      'type' => one(doc, 'type_ssim'),
      'rights' => one(doc, 'rights_ssm'),
      'institution' => { 'id' => doc['source_ssi'], 'name' => one(doc, 'institution_ssim') },
      'links' => { 'portal' => "#{BASE}/catalog/#{doc['id']}", 'source' => one(doc, 'url_ssm'),
                   'pdf' => one(doc, 'pdf_url_ssm'), 'api' => "#{BASE}/api/v1/records/#{doc['id']}" },
      'files' => files(doc),
      'updated_at' => doc['updated_dtsi']
    }
  end

  def to_csv_row(doc)
    h = to_h(doc)
    j = ->(a) { Array(a).join('||') }
    [h['id'], h['title'], j[h['authors']], j[h['supervisors']], h['year'], h['degree'], h['degree_level'],
     h['discipline'], j[h['faculty']], j[h['department']], j[h['subjects']], h['abstract'], h['institution']['name'],
     h['institution']['id'], h['language'], h['rights'], h['links']['portal'], h['links']['source'], h['links']['pdf'],
     h['updated_at']]
  end
end
