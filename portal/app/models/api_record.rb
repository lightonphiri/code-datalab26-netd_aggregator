# frozen_string_literal: true

# Stable public representation of a record for the REST API v1 (SRS EI-6), independent of Solr field names.
module ApiRecord
  BASE = Netd.base_url
  FIELDS = %w[id updated_dtsi added_dtsi title_ssm author_ssim supervisor_ssim subject_ssim abstract_tesim year_isi degree_ssim
              degree_level_ssim discipline_ssim faculty_ssim department_ssim institution_ssim source_ssi language_ssim
              type_ssim rights_ssm url_ssm pdf_url_ssm files_ssm derived_ssm fos_ssm duplicate_of_ssi duplicates_ssim
              openalex_id_ssi cited_by_isi cited_by_ssm].join(',')
  CSV_COLUMNS = %w[id title authors supervisors year degree degree_level discipline faculty department subjects abstract
                   institution institution_id language rights portal_url source_url pdf_url updated_at fields_of_study added_at duplicate_of
                   openalex_id cited_by_count].freeze

  # canonical field -> API field, for the "derived" object (FR-50)
  API_NAMES = { 'supervisor' => 'supervisors', 'subject' => 'subjects', 'author' => 'authors' }.freeze

  module_function

  # { "degree_level" => { "method" => "model:titlepage-rules-1", "confidence" => 0.96 } } for values filled by a model
  def derived(doc)
    Array(doc['derived_ssm']).each_with_object({}) do |j, h|
      d = JSON.parse(j)
      h[API_NAMES.fetch(d['field'], d['field'])] = { 'method' => d['method'], 'confidence' => d['confidence'] }
    rescue JSON::ParserError
      next
    end
  end

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

  # OpenAlex fields of study (FR-55, FR-56): id, name, level, field, domain, OpenAlex URI and confidence
  def fields_of_study(doc)
    conf = derived(doc).dig('field_of_study', 'confidence')
    Array(doc['fos_ssm']).filter_map do |j|
      f = JSON.parse(j)
      { 'id' => f['id'], 'uri' => "https://openalex.org/#{f['id']}", 'name' => f['name'], 'level' => f['level'],
        'field' => f['field'], 'domain' => f['domain'], 'confidence' => conf }
    rescue JSON::ParserError
      nil
    end
  end

  # Works citing the thesis, from OpenAlex (FR-69, API 1.7.0): nil count when the thesis has not been matched in
  # OpenAlex (not yet checked, or no confident match); 0 when matched and not cited.
  def cited_by(doc)
    return { 'count' => nil, 'works' => [] } unless doc['openalex_id_ssi']

    works = Array(doc['cited_by_ssm']).filter_map do |j|
      c = JSON.parse(j)
      { 'openalex_id' => c['id'], 'title' => c['title'], 'year' => c['year'], 'type' => c['type'], 'url' => c['url'] }
    rescue JSON::ParserError
      nil
    end
    { 'count' => doc['cited_by_isi'].to_i, 'works' => works }
  end

  def to_h(doc)
    {
      'id' => doc['id'],
      'oai_identifier' => "oai:#{Netd.host}:#{doc['id']}",
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
      'fields_of_study' => fields_of_study(doc),
      'language' => one(doc, 'language_ssim'),
      'type' => one(doc, 'type_ssim'),
      'rights' => one(doc, 'rights_ssm'),
      'institution' => { 'id' => doc['source_ssi'], 'name' => one(doc, 'institution_ssim') },
      'links' => { 'portal' => "#{BASE}/theses/#{ThesisId.short(doc['id'])}", 'source' => one(doc, 'url_ssm'),
                   'pdf' => one(doc, 'pdf_url_ssm'), 'api' => "#{BASE}/api/v1/records/#{doc['id']}" },
      'files' => files(doc),
      'derived' => derived(doc),
      'updated_at' => doc['updated_dtsi'],
      'added_at' => doc['added_dtsi'],
      'duplicate_of' => doc['duplicate_of_ssi'],     # FR-19: id of the main record when this is another copy
      'other_copies' => list(doc, 'duplicates_ssim'), # FR-19: ids of the other copies of a main record
      'openalex_id' => doc['openalex_id_ssi'],         # FR-69: the thesis as an OpenAlex work (W...)
      'cited_by' => cited_by(doc)                      # FR-69: works citing it, from OpenAlex
    }
  end

  def to_csv_row(doc)
    h = to_h(doc)
    j = ->(a) { Array(a).join('||') }
    [h['id'], h['title'], j[h['authors']], j[h['supervisors']], h['year'], h['degree'], h['degree_level'],
     h['discipline'], j[h['faculty']], j[h['department']], j[h['subjects']], h['abstract'], h['institution']['name'],
     h['institution']['id'], h['language'], h['rights'], h['links']['portal'], h['links']['source'], h['links']['pdf'],
     h['updated_at'], j[h['fields_of_study'].map { |f| f['name'] }], h['added_at'], h['duplicate_of'],
     h['openalex_id'], h.dig('cited_by', 'count')]
  end
end
