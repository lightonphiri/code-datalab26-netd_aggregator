# frozen_string_literal: true

require 'builder'

# OAI-PMH 2.0 data provider for the portal's cleaned records (SRS EI-4; SDD "OAI-PMH data provider").
#
# Base URL https://netd.ac.zm/oai, GET or POST, all six verbs, formats oai_dc and etdms (ETD-MS v1.1).
# Records are read from Solr only. The datestamp is updated_dtsi: the last change of the record's content in
# the portal (seconds granularity, UTC). Sets: inst:<source id> per institution and level:<masters|doctoral>.
# Resumption tokens are stateless (Base64 JSON holding the Solr cursorMark, the request filters and an expiry).
# Records removed by the harvester disappear from Solr, so deletedRecord is "transient".
class OaiController < ActionController::Base
  skip_forgery_protection

  BASE_URL = 'https://netd.ac.zm/oai'
  REPOSITORY_ID = 'netd.ac.zm'
  ADMIN_EMAIL = 'datalab@unza.zm'
  PAGE_SIZE = 100
  TOKEN_TTL = 24 * 3600
  PORTAL_RECORD_URL = 'https://netd.ac.zm/catalog/'
  LEVELS = { 'masters' => 'Masters', 'doctoral' => 'Doctoral', 'postgraduate-diploma' => 'Postgraduate Diploma' }.freeze
  LEVEL_NAMES = { 'masters' => "Master's theses and dissertations", 'doctoral' => 'Doctoral theses',
                  'postgraduate-diploma' => 'Postgraduate diploma reports and dissertations' }.freeze

  FORMATS = {
    'oai_dc' => { schema: 'http://www.openarchives.org/OAI/2.0/oai_dc.xsd',
                  ns: 'http://www.openarchives.org/OAI/2.0/oai_dc/' },
    'etdms' => { schema: 'http://www.ndltd.org/standards/metadata/etdms/1-1/etdms11.xsd',
                 ns: 'http://www.ndltd.org/standards/metadata/etdms/1.1/' }
  }.freeze

  VERBS = {
    'Identify' => { required: [], optional: [] },
    'ListMetadataFormats' => { required: [], optional: %w[identifier] },
    'ListSets' => { required: [], optional: [], exclusive: 'resumptionToken' },
    'ListIdentifiers' => { required: %w[metadataPrefix], optional: %w[from until set], exclusive: 'resumptionToken' },
    'ListRecords' => { required: %w[metadataPrefix], optional: %w[from until set], exclusive: 'resumptionToken' },
    'GetRecord' => { required: %w[identifier metadataPrefix], optional: [] }
  }.freeze

  FIELDS = %w[id updated_dtsi title_ssm author_ssim supervisor_ssim subject_ssim fos_ssm abstract_tesim year_ssim
              degree_ssim degree_level_ssim discipline_ssim faculty_ssim department_ssim institution_ssim
              source_ssi language_ssim type_ssim rights_ssm url_ssm pdf_url_ssm].join(',')

  class OaiError < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  after_action { UsageCount.bump('oai', record_id: params[:verb].to_s.first(30)) } # usage analytics, FR-61

  def index
    @args = parse_arguments
    @verb = @args['verb']
    body = begin
      check_arguments
      send("verb_#{@verb.underscore}")
    rescue OaiError => e
      envelope(echo_args: !%w[badVerb badArgument].include?(e.code)) { |x| x.error(e.message, code: e.code) }
    end
    response.headers['Cache-Control'] = 'no-cache'
    render xml: body, content_type: 'text/xml; charset=utf-8'
  end

  private

  # --- request handling --------------------------------------------------------------------------------

  # Arguments from the query string and (for POST) the form body; a repeated argument is an error.
  def parse_arguments
    raw = request.query_string.to_s
    raw = [raw, request.raw_post.to_s].reject(&:empty?).join('&') if request.post?
    pairs = URI.decode_www_form(raw)
    names = pairs.map(&:first)
    @repeated = names.select { |n| names.count(n) > 1 }.uniq
    pairs.to_h
  rescue ArgumentError
    @repeated = []
    { '__malformed' => '' }
  end

  def check_arguments
    raise OaiError.new('badVerb', 'Missing verb argument') if @verb.blank?
    raise OaiError.new('badVerb', "Illegal verb: #{@verb}") unless VERBS.key?(@verb)
    raise OaiError.new('badArgument', "Repeated argument: #{@repeated.join(', ')}") if @repeated.any?

    spec = VERBS[@verb]
    given = @args.keys - ['verb']
    if spec[:exclusive] && given.include?(spec[:exclusive])
      others = given - [spec[:exclusive]]
      raise OaiError.new('badArgument', "#{spec[:exclusive]} is an exclusive argument") if others.any?

      return
    end
    illegal = given - spec[:required] - spec[:optional]
    raise OaiError.new('badArgument', "Illegal argument: #{illegal.join(', ')}") if illegal.any?

    missing = spec[:required].reject { |a| @args[a].present? }
    raise OaiError.new('badArgument', "Missing argument: #{missing.join(', ')}") if missing.any?
  end

  # --- verbs ---------------------------------------------------------------------------------------------

  def verb_identify
    envelope do |x|
      x.Identify do
        x.repositoryName 'Zambia National ETD Portal'
        x.baseURL BASE_URL
        x.protocolVersion '2.0'
        x.adminEmail ADMIN_EMAIL
        x.earliestDatestamp earliest_datestamp
        x.deletedRecord 'transient'
        x.granularity 'YYYY-MM-DDThh:mm:ssZ'
        x.description do
          x.tag!('oai-identifier', 'xmlns' => 'http://www.openarchives.org/OAI/2.0/oai-identifier',
                                   'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
                                   'xsi:schemaLocation' => 'http://www.openarchives.org/OAI/2.0/oai-identifier ' \
                                                           'http://www.openarchives.org/OAI/2.0/oai-identifier.xsd') do
            x.scheme 'oai'
            x.repositoryIdentifier REPOSITORY_ID
            x.delimiter ':'
            x.sampleIdentifier "oai:#{REPOSITORY_ID}:unza-123456789-9150"
          end
        end
      end
    end
  end

  def verb_list_metadata_formats
    fetch_one(@args['identifier']) if @args['identifier']
    envelope do |x|
      x.ListMetadataFormats do
        FORMATS.each do |prefix, f|
          x.metadataFormat do
            x.metadataPrefix prefix
            x.schema f[:schema]
            x.metadataNamespace f[:ns]
          end
        end
      end
    end
  end

  def verb_list_sets
    raise OaiError.new('badResumptionToken', 'This repository does not issue resumption tokens for ListSets') if @args['resumptionToken']

    insts = institutions
    envelope do |x|
      x.ListSets do
        insts.each do |source, name|
          x.set do
            x.setSpec "inst:#{source}"
            x.setName name
          end
        end
        LEVELS.each_key do |key|
          x.set do
            x.setSpec "level:#{key}"
            x.setName LEVEL_NAMES[key]
          end
        end
      end
    end
  end

  def verb_get_record
    prefix = check_prefix(@args['metadataPrefix'])
    doc = fetch_one(@args['identifier'])
    envelope { |x| x.GetRecord { record(x, doc, prefix) } }
  end

  def verb_list_identifiers = list(headers_only: true)
  def verb_list_records = list(headers_only: false)

  def list(headers_only:)
    state = if @args['resumptionToken']
              decode_token(@args['resumptionToken'])
            else
              { 'p' => check_prefix(@args['metadataPrefix']), 's' => @args['set'], 'n' => 0, 'c' => '*' }
                .merge(date_range(@args['from'], @args['until']))
            end
    res = solr(q: '*:*', fq: filters(state), sort: 'id asc', rows: PAGE_SIZE, cursorMark: state['c'],
               fl: headers_only ? 'id,updated_dtsi,source_ssi,degree_level_ssim' : FIELDS)
    docs = res['response']['docs']
    total = res['response']['numFound']
    raise OaiError.new('noRecordsMatch', 'No records match the request') if docs.empty? && state['n'].zero?

    shown = state['n'] + docs.size
    next_token = (encode_token(state.merge('c' => res['nextCursorMark'], 'n' => shown)) if shown < total && docs.any?)
    envelope do |x|
      x.tag!(headers_only ? 'ListIdentifiers' : 'ListRecords') do
        docs.each { |d| headers_only ? header(x, d) : record(x, d, state['p']) }
        if @args['resumptionToken'] || next_token
          attrs = { completeListSize: total, cursor: state['n'] }
          attrs[:expirationDate] = Time.at(Time.now.to_i + TOKEN_TTL).utc.iso8601 if next_token
          x.resumptionToken(next_token.to_s, attrs)
        end
      end
    end
  end

  # --- arguments ----------------------------------------------------------------------------------------

  def check_prefix(prefix)
    raise OaiError.new('cannotDisseminateFormat', "Unsupported metadataPrefix: #{prefix}") unless FORMATS.key?(prefix)

    prefix
  end

  DAY = /\A\d{4}-\d{2}-\d{2}\z/
  SECOND = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/

  # from/until -> Solr range bounds (inclusive). Day granularity covers the whole day.
  def date_range(from, till)
    out = {}
    [['f', from, false], ['u', till, true]].each do |key, v, upper|
      next if v.nil?
      raise OaiError.new('badArgument', "Illegal date: #{v}") unless v.match?(DAY) || v.match?(SECOND)

      t = begin
        Time.iso8601(v.match?(DAY) ? "#{v}T00:00:00Z" : v)
      rescue ArgumentError
        raise OaiError.new('badArgument', "Illegal date: #{v}")
      end
      t += 86_399 if upper && v.match?(DAY)
      out[key] = t.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    end
    if from && till
      raise OaiError.new('badArgument', 'from and until have different granularities') if from.length != till.length
      raise OaiError.new('badArgument', 'from is later than until') if out['f'] > out['u']
    end
    out
  end

  def filters(state)
    fq = []
    if state['s'].present?
      kind, value = state['s'].split(':', 2)
      case kind
      when 'inst'
        raise OaiError.new('noRecordsMatch', "No such set: #{state['s']}") unless institutions.key?(value)

        fq << "source_ssi:#{solr_escape(value)}"
      when 'level'
        raise OaiError.new('noRecordsMatch', "No such set: #{state['s']}") unless LEVELS.key?(value)

        fq << "degree_level_ssim:#{LEVELS[value]}"
      else
        raise OaiError.new('noRecordsMatch', "No such set: #{state['s']}")
      end
    end
    fq << "updated_dtsi:[#{state['f'] || '*'} TO #{state['u'] || '*'}]" if state['f'] || state['u']
    fq
  end

  # --- resumption tokens ----------------------------------------------------------------------------------

  def encode_token(state)
    Base64.urlsafe_encode64(state.merge('e' => Time.now.to_i + TOKEN_TTL).compact.to_json, padding: false)
  end

  def decode_token(token)
    state = JSON.parse(Base64.urlsafe_decode64(token))
    raise ArgumentError unless state.is_a?(Hash) && FORMATS.key?(state['p']) && state['c'].is_a?(String) &&
                               state['n'].is_a?(Integer) && state['e'].is_a?(Integer)
    raise OaiError.new('badResumptionToken', 'The resumptionToken has expired') if state['e'] < Time.now.to_i

    state
  rescue ArgumentError, JSON::ParserError
    raise OaiError.new('badResumptionToken', 'The resumptionToken is invalid')
  end

  # --- Solr --------------------------------------------------------------------------------------------------

  def solr(params)
    defaults = { defType: 'lucene', facet: false, spellcheck: false, wt: 'json' }
    Blacklight.default_index.connection.get('select', params: defaults.merge(params))
  end

  def solr_escape(value) = value.gsub(/([+\-&|!(){}\[\]^"~*?:\\\/\s])/) { "\\#{Regexp.last_match(1)}" }

  def fetch_one(identifier)
    prefix = "oai:#{REPOSITORY_ID}:"
    id = identifier.to_s.start_with?(prefix) ? identifier.to_s.delete_prefix(prefix) : nil
    doc = id.present? && solr(q: "id:#{solr_escape(id)}", rows: 1, fl: FIELDS)['response']['docs'].first
    raise OaiError.new('idDoesNotExist', "Unknown identifier: #{identifier}") unless doc

    doc
  end

  # source id -> institution name, for institutions that have records.
  def institutions
    @institutions ||= begin
      res = solr(q: '*:*', rows: 0, facet: true, 'facet.pivot': 'source_ssi,institution_ssim', 'facet.limit': -1)
      (res.dig('facet_counts', 'facet_pivot', 'source_ssi,institution_ssim') || []).sort_by { |p| p['value'] }
        .to_h { |p| [p['value'], p.dig('pivot', 0, 'value') || p['value']] }
    end
  end

  def earliest_datestamp
    doc = solr(q: 'updated_dtsi:*', rows: 1, sort: 'updated_dtsi asc', fl: 'updated_dtsi')['response']['docs'].first
    datestamp(doc) || '2011-01-01T00:00:00Z'
  end

  def datestamp(doc)
    v = doc && doc['updated_dtsi']
    v && Time.iso8601(v).utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  end

  # --- XML ------------------------------------------------------------------------------------------------------

  def envelope(echo_args: true)
    x = Builder::XmlMarkup.new(indent: 1)
    x.instruct! :xml, version: '1.0', encoding: 'UTF-8'
    x.tag!('OAI-PMH', 'xmlns' => 'http://www.openarchives.org/OAI/2.0/',
                      'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
                      'xsi:schemaLocation' => 'http://www.openarchives.org/OAI/2.0/ ' \
                                              'http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd') do
      x.responseDate Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      attrs = echo_args ? @args.slice('verb', *VERBS.values.flat_map { |s| s[:required] + s[:optional] + [s[:exclusive]].compact }) : {}
      x.request(BASE_URL, attrs)
      yield x
    end
    x.target!
  end

  def header(x, doc)
    x.header do
      x.identifier "oai:#{REPOSITORY_ID}:#{doc['id']}"
      x.datestamp datestamp(doc) || earliest_datestamp
      x.setSpec "inst:#{doc['source_ssi']}" if doc['source_ssi']
      Array(doc['degree_level_ssim']).each do |lvl|
        key = LEVELS.key(lvl)
        x.setSpec "level:#{key}" if key
      end
    end
  end

  def record(x, doc, prefix)
    x.record do
      header(x, doc)
      x.metadata { prefix == 'etdms' ? etdms(x, doc) : oai_dc(x, doc) }
    end
  end

  XML_ILLEGAL = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/

  def values(doc, field) = Array(doc[field]).map { |v| v.to_s.gsub(XML_ILLEGAL, ' ').strip }.reject(&:empty?).uniq

  def identifiers(doc) = ["#{PORTAL_RECORD_URL}#{doc['id']}", *values(doc, 'url_ssm'), *values(doc, 'pdf_url_ssm')].uniq

  def types(doc) = (['Electronic Thesis or Dissertation', 'Text'] + values(doc, 'type_ssim')).uniq

  def subjects(doc)
    s = values(doc, 'subject_ssim')
    s.empty? ? values(doc, 'discipline_ssim') : s
  end

  # Standard fields of study (OpenAlex Topics, FR-56): [[name, uri], ...]
  def fields_of_study(doc)
    values(doc, 'fos_ssm').filter_map do |j|
      f = JSON.parse(j)
      [f['name'], "https://openalex.org/#{f['id']}"]
    rescue JSON::ParserError
      nil
    end
  end

  def oai_dc(x, doc)
    x.tag!('oai_dc:dc', 'xmlns:oai_dc' => FORMATS['oai_dc'][:ns], 'xmlns:dc' => 'http://purl.org/dc/elements/1.1/',
                        'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
                        'xsi:schemaLocation' => "#{FORMATS['oai_dc'][:ns]} #{FORMATS['oai_dc'][:schema]}") do
      values(doc, 'title_ssm').each { |v| x.tag!('dc:title', v) }
      values(doc, 'author_ssim').each { |v| x.tag!('dc:creator', v) }
      subjects(doc).each { |v| x.tag!('dc:subject', v) }
      fields_of_study(doc).each { |name, uri| x.tag!('dc:subject', name); x.tag!('dc:subject', uri) }
      values(doc, 'abstract_tesim').each { |v| x.tag!('dc:description', v) }
      values(doc, 'institution_ssim').each { |v| x.tag!('dc:publisher', v) }
      values(doc, 'supervisor_ssim').each { |v| x.tag!('dc:contributor', v) }
      values(doc, 'year_ssim').each { |v| x.tag!('dc:date', v) }
      types(doc).each { |v| x.tag!('dc:type', v) }
      identifiers(doc).each { |v| x.tag!('dc:identifier', v) }
      values(doc, 'language_ssim').each { |v| x.tag!('dc:language', v) }
      values(doc, 'rights_ssm').each { |v| x.tag!('dc:rights', v) }
    end
  end

  # ETD-MS v1.1: elements in schema order (title ... rights, then degree).
  def etdms(x, doc)
    ns = FORMATS['etdms'][:ns]
    x.thesis('xmlns' => ns, 'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
             'xsi:schemaLocation' => "#{ns} #{FORMATS['etdms'][:schema]}") do
      values(doc, 'title_ssm').each { |v| x.title v }
      values(doc, 'author_ssim').each { |v| x.creator v }
      subjects(doc).each { |v| x.subject v }
      fields_of_study(doc).each { |name, _uri| x.subject(name, scheme: 'OpenAlex') }
      values(doc, 'abstract_tesim').each { |v| x.description v }
      values(doc, 'institution_ssim').each { |v| x.publisher v }
      values(doc, 'supervisor_ssim').each { |v| x.contributor(v, role: 'advisor') }
      values(doc, 'year_ssim').first(1).each { |v| x.date v }
      types(doc).each { |v| x.type v }
      x.format 'application/pdf' if values(doc, 'pdf_url_ssm').any?
      identifiers(doc).each { |v| x.identifier v }
      values(doc, 'language_ssim').each { |v| x.language v }
      values(doc, 'rights_ssm').each { |v| x.rights v }
      degree = { name: values(doc, 'degree_ssim'), level: values(doc, 'degree_level_ssim'),
                 discipline: values(doc, 'discipline_ssim').presence || values(doc, 'department_ssim'),
                 grantor: values(doc, 'institution_ssim') }
      next if degree.values.all?(&:empty?)

      x.degree do
        degree.each { |el, vals| vals.each { |v| x.tag!(el.to_s, v) } }
      end
    end
  end
end
