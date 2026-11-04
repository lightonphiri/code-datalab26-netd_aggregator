# frozen_string_literal: true

# Reports for HEA (SRS FR-63): predefined per-institution reports, reports by supervisor and custom reports, built from
# the Solr index and rendered as Excel (ReportXlsx), PDF (ReportPdf) or an HTML preview. Signed-in administrators only.
# Counts are of distinct theses: other copies of a thesis deposited twice are left out, as in search results (FR-19).
# Usage figures (FR-61) are added when asked for; they are a lower bound (portal Download links only, crawlers filtered).
class HeaReport
  Section = Struct.new(:title, :headers, :rows, :note, :chart, :total, :kind, keyword_init: true)

  MAIN = '-duplicate_of_ssi:[* TO *]'
  LEVELS = ['Doctoral', 'Masters', 'Postgraduate Diploma'].freeze
  NOT_RECORDED = 'Not recorded'
  LIST_MAX = 20_000
  CITED = 'cited_by_isi:[1 TO *]'     # FR-69
  MATCHED = 'openalex_id_ssi:[* TO *]' # FR-69: found in OpenAlex
  MOST_CITED = 20

  # grouping and filter fields offered in custom reports: key => [label, Solr field]
  GROUPS = {
    'institution' => ['Institution', 'institution_ssim'], 'year' => ['Year', 'year_ssim'],
    'degree_level' => ['Degree level', 'degree_level_ssim'], 'type' => ['Type', 'type_ssim'],
    'faculty' => ['Faculty / School', 'faculty_ssim'], 'department' => ['Department', 'department_ssim'],
    'degree' => ['Degree', 'degree_ssim'], 'discipline' => ['Programme / Discipline', 'discipline_ssim'],
    'supervisor' => ['Supervisor', 'supervisor_ssim'], 'fos_domain' => ['Research domain', 'fos_domain_ssim'],
    'fos_field' => ['Field of study', 'fos_field_ssim'], 'language' => ['Language', 'language_ssim']
  }.freeze

  # columns offered in record listings: key => label
  COLUMNS = {
    'title' => 'Title', 'authors' => 'Author(s)', 'supervisors' => 'Supervisor(s)', 'year' => 'Year',
    'degree' => 'Degree', 'degree_level' => 'Degree level', 'faculty' => 'Faculty / School',
    'department' => 'Department', 'discipline' => 'Programme / Discipline', 'institution' => 'Institution',
    'type' => 'Type', 'subjects' => 'Keywords', 'fields_of_study' => 'Fields of study', 'language' => 'Language',
    'full_text' => 'Full text', 'filled' => 'Filled by the portal', 'cited_by' => 'Cited by (OpenAlex)',
    'portal_url' => 'Portal link',
    'source_url' => 'Repository link'
  }.freeze
  DEFAULT_COLUMNS = %w[title authors supervisors year degree_level faculty department institution portal_url].freeze

  # filter keys accepted from the form, with the Solr field used for exact values
  TERM_FILTERS = { 'degree_level' => 'degree_level_ssim', 'type' => 'type_ssim', 'faculty' => 'faculty_ssim',
                   'department' => 'department_ssim', 'fos_field' => 'fos_field_ssim' }.freeze

  attr_reader :kind, :title, :subtitle, :filters, :sections, :notes, :generated_at
  attr_accessor :slug

  def initialize(kind, title, subtitle, filters)
    @kind = kind
    @title = title
    @subtitle = subtitle
    @filters = filters
    @sections = []
    @notes = []
    @generated_at = Time.now.utc
  end

  def add(**kw) = (@sections << Section.new(**kw)).last
  def filename(ext) = "netd-report-#{kind}-#{slug || 'all'}-#{generated_at.strftime('%Y-%m-%d')}.#{ext}"
  def self.date(d) = d.strftime('%B %-d, %Y')

  # ---- filters ---------------------------------------------------------------------------------------------------

  # Parsed form filters: institution (source id), years, exact facet values, supervisor name part, words.
  class Filters
    attr_reader :p

    def initialize(params)
      @p = params.to_h.transform_keys(&:to_s).transform_values { |v| v.is_a?(String) ? v.strip : v }
    end

    def source = p['institution'].to_s[/\A[a-z0-9_-]+\z/]
    def year_from = p['year_from'].to_s[/\A\d{4}\z/]&.to_i
    def year_to = p['year_to'].to_s[/\A\d{4}\z/]&.to_i
    def supervisor = p['supervisor'].presence
    def words = p['words'].presence
    def term(key) = p[key].presence
    def cited = p['cited'].to_s == '1' # FR-69: only theses cited by at least one work in OpenAlex

    def institution_name
      return nil unless source

      InstitutionRegistry.all.find { |i| i[:source] == source }&.dig(:name) || source.upcase
    end

    def slug = source || 'all'

    # [label, value] pairs describing the filters, for the report header
    def describe(supervisor_names = nil)
      d = [['Institution', institution_name || 'All institutions']]
      d << ['Years', "#{year_from || 'earliest'} to #{year_to || 'latest'}"] if year_from || year_to
      TERM_FILTERS.each_key { |k| d << [GROUPS.fetch(k, [k.humanize]).first, term(k)] if term(k) }
      if supervisor
        d << ['Supervisor name contains', supervisor]
        d << ['Supervisor names matched', supervisor_names.size.to_s] if supervisor_names
      end
      d << ['Words in title or abstract', words] if words
      d << ['Citations (OpenAlex)', 'Cited theses only'] if cited
      d
    end
  end

  def self.esc(v) = v.to_s.gsub(/[\\"]/) { |c| "\\#{c}" }
  def self.term_fq(field, value) = "#{field}:\"#{esc(value)}\""

  # Solr filter queries for the filters (main records only). Returns [fq, supervisor names matched or nil].
  def self.fqs(f, main: true)
    fq = main ? [MAIN] : []
    fq << term_fq('source_ssi', f.source) if f.source
    fq << "year_isi:[#{f.year_from || '*'} TO #{f.year_to || '*'}]" if f.year_from || f.year_to
    TERM_FILTERS.each { |k, field| fq << term_fq(field, f.term(k)) if f.term(k) }
    fq << CITED if f.cited
    names = nil
    if f.supervisor
      names = supervisor_names(fq, f.supervisor)
      fq << (names.empty? ? '-*:*' : "supervisor_ssim:(#{names.map { |n| "\"#{esc(n)}\"" }.join(' OR ')})")
    end
    [fq, names]
  end

  # supervisor values (as recorded) containing the given text, ignoring case, dots and spacing
  def self.supervisor_names(fq, text)
    key = ->(s) { s.to_s.downcase.gsub(/[^[:alnum:]]+/, ' ').strip }
    want = key[text]
    facet('supervisor_ssim', fq, missing: false).map(&:first).select { |n| key[n].include?(want) }
  end

  # ---- Solr ------------------------------------------------------------------------------------------------------

  def self.solr(params, words = nil)
    base = { q: '*:*', defType: 'lucene', rows: 0, wt: 'json' }
    base = base.merge(q: words, defType: 'edismax', qf: 'title_tsim abstract_tesim', 'q.op': 'AND') if words
    Blacklight.default_index.connection.get('select', params: base.merge(params))
  end

  def self.count(fq, words = nil) = solr({ fq: fq }, words).dig('response', 'numFound').to_i

  # [[value, count], ...] (nil value = missing) sorted by count, or by value when sort: 'index'
  def self.facet(field, fq, words = nil, missing: true, sort: 'count', limit: -1)
    res = solr({ fq: fq, facet: true, 'facet.field': field, 'facet.limit': limit, 'facet.mincount': 1,
                 'facet.missing': missing, 'facet.sort': sort }, words)
    res.dig('facet_counts', 'facet_fields', field).to_a.each_slice(2).map { |v, n| [v, n.to_i] }.reject { |_, n| n.zero? }
  end

  # { value => { sub_value => count } } from a two-level pivot
  def self.pivot(a, b, fq, words = nil)
    res = solr({ fq: fq, facet: true, 'facet.pivot': "#{a},#{b}", 'facet.limit': -1, 'facet.mincount': 1 }, words)
    res.dig('facet_counts', 'facet_pivot', "#{a},#{b}").to_a.to_h do |p|
      [p['value'], Array(p['pivot']).to_h { |c| [c['value'], c['count'].to_i] }.merge(:total => p['count'].to_i)]
    end
  end

  def self.each_doc(fq, words = nil, sort: 'year_isi desc, id asc', max: LIST_MAX)
    cursor = '*'
    seen = 0
    loop do
      res = solr({ fq: fq, rows: 500, sort: sort, cursorMark: cursor, fl: ApiRecord::FIELDS }, words)
      res.dig('response', 'docs').to_a.each do |d|
        return if seen >= max

        yield d
        seen += 1
      end
      break if res['nextCursorMark'] == cursor

      cursor = res['nextCursorMark']
    end
  end

  def self.pct(n, total) = total.positive? ? (100.0 * n / total).round(1) : 0.0
  def self.label(v) = v.nil? || v.to_s.empty? ? NOT_RECORDED : v.to_s

  def self.year_sorted(rows) = rows.sort_by { |v, _| v.nil? ? 99_999 : v.to_i }

  # ---- listing values --------------------------------------------------------------------------------------------

  def self.value(h, doc, col)
    case col
    when 'title', 'degree', 'degree_level', 'discipline', 'type', 'language', 'year' then h[col]
    when 'authors', 'supervisors', 'faculty', 'department', 'subjects' then Array(h[col]).join('; ')
    when 'institution' then h.dig('institution', 'name')
    when 'fields_of_study' then h['fields_of_study'].map { |f| f['name'] }.join('; ')
    when 'full_text' then h.dig('links', 'pdf') ? 'PDF' : ''
    when 'filled' then filled(h)
    when 'cited_by' then h.dig('cited_by', 'count')
    when 'portal_url' then h.dig('links', 'portal')
    when 'source_url' then h.dig('links', 'source')
    else doc[col]
    end
  end

  # "supervisors (model); degree_level (correction)" for values the portal filled in (FR-50)
  def self.filled(h)
    h['derived'].map do |f, d|
      how = d['method'].to_s.start_with?('model') ? 'model' : d['method'].to_s.split(':').first
      "#{f.tr('_', ' ')} (#{how})"
    end.join('; ')
  end

  # ---- predefined report: institution ----------------------------------------------------------------------------

  def self.institution(params, usage: false)
    f = Filters.new(params)
    fq, = fqs(f)
    words = f.words
    r = new('institution', "ETDs: #{f.institution_name || 'all institutions'}",
            'Theses and dissertations by year, type, degree level, faculty and department', f.describe)
    r.slug = f.slug
    total = count(fq, words)
    r.summary_section(fq, f, words, total)
    r.institutions_section(fq, words) unless f.source
    years = year_sorted(facet('year_ssim', fq, words))
    r.add(title: 'By year', headers: %w[Year Theses], rows: years.map { |v, n| [label(v), n] }, chart: :column, total: true)
    levels = facet('degree_level_ssim', fq, words)
    r.add(title: 'By degree level', headers: ['Degree level', 'Theses', '% of all'],
          rows: levels.map { |v, n| [label(v), n, pct(n, total)] }, chart: :bar, total: true)
    r.year_level_section(fq, words)
    types = facet('type_ssim', fq, words)
    r.add(title: 'By type', headers: %w[Type Theses], rows: types.map { |v, n| [label(v), n] }, chart: :bar, total: true,
          note: 'Type as given by the repository; "Other" and article or book types are mostly collection placeholders.')
    facs = facet('faculty_ssim', fq, words)
    r.add(title: 'By faculty / School', headers: ['Faculty / School', 'Theses', '% of all'],
          rows: facs.map { |v, n| [label(v), n, pct(n, total)] }, chart: :bar, total: true)
    r.faculty_department_section(fq, words)
    degrees = facet('degree_ssim', fq, words)
    r.add(title: 'By degree', headers: %w[Degree Theses], rows: degrees.map { |v, n| [label(v), n] }, total: true,
          note: 'Degree names as read from the repository or the title page.')
    r.citation_sections(fq, f, words)
    r.usage_sections(f) if usage
    r.notes.push(*standard_notes)
    r
  end

  def self.standard_notes
    ['Counts are of distinct theses: when a thesis was deposited more than once, only the main record is counted (other copies are listed under it on the portal).',
     'Values missing in the repository were filled by the portal where possible (title-page reading models and manual corrections); the Excel listing marks them in "Filled by the portal".',
     '"Not recorded" means neither the repository nor the portal has the value. A thesis with two faculties, departments or supervisors is counted under each, so those columns can add up to more than the total.']
  end

  def summary_section(fq, f, words, total)
    k = self.class
    with = lambda { |extra| n = k.count(fq + [extra], words); [n, k.pct(n, total)] }
    copies = k.count(k.fqs(f, main: false).first + ['duplicate_of_ssi:[* TO *]'], words)
    st = k.solr({ fq: fq, stats: true, 'stats.field': 'year_isi' }, words).dig('stats', 'stats_fields', 'year_isi') || {}
    rows = [['Distinct theses and dissertations', total, nil],
            ['Other copies of the same thesis (not counted)', copies, nil],
            ['Years covered', st['min'] ? "#{st['min'].to_i} to #{st['max'].to_i}" : NOT_RECORDED, nil]]
    { 'With supervisor recorded' => 'supervisor_ssim', 'With degree level' => 'degree_level_ssim',
      'With degree name' => 'degree_ssim', 'With faculty / School' => 'faculty_ssim',
      'With department' => 'department_ssim', 'With abstract' => 'abstract_tesim',
      'With a field of study (OpenAlex)' => 'fos_field_ssim' }.each do |lab, field|
      rows << [lab, *with.call("#{field}:[* TO *]")]
    end
    rows << ['With a full-text PDF link', *with.call(k.term_fq('full_text_ssim', 'PDF available'))]
    rows << ['Found in OpenAlex', *with.call(MATCHED)]
    rows << ['Cited at least once (OpenAlex)', *with.call(CITED)]
    add(title: 'Summary', headers: ['Measure', 'Value', '% of theses'], rows: rows, kind: :summary)
  end

  def institutions_section(fq, words)
    counts = self.class.facet('source_ssi', fq, words, missing: false).to_h
    rows = InstitutionRegistry.all.map do |i|
      [i[:name], counts[i[:source]].to_i, InstitutionRegistry::STATUS_LABELS.fetch(i[:status].to_s, i[:status].to_s)]
    end.sort_by { |name, n, _| [-n, name] }
    add(title: 'By institution', headers: ['Institution', 'Theses', 'Status'], rows: rows, chart: :bar, total: true,
        note: 'All HEA institutions with accredited postgraduate programmes; 0 where nothing has been harvested yet.')
  end

  def year_level_section(fq, words)
    pv = self.class.pivot('year_ssim', 'degree_level_ssim', fq, words)
    rows = self.class.year_sorted(pv.to_a).map do |year, h|
      known = LEVELS.sum { |l| h[l].to_i }
      [year, *LEVELS.map { |l| h[l].to_i }, [h[:total] - known, 0].max, h[:total]]
    end
    add(title: 'By year and degree level', headers: ['Year', *LEVELS, NOT_RECORDED, 'Total'], rows: rows, total: true,
        chart: :stacked)
  end

  def faculty_department_section(fq, words)
    pv = self.class.pivot('faculty_ssim', 'department_ssim', fq, words)
    rows = []
    pv.sort_by { |fac, h| [-h[:total], fac] }.each do |fac, h|
      deps = h.except(:total).sort_by { |d, n| [-n, d] }
      deps.each { |d, n| rows << [fac, d, n] }
      rest = h[:total] - deps.sum { |_, n| n }
      rows << [fac, NOT_RECORDED, rest] if rest.positive?
    end
    add(title: 'By faculty and department', headers: ['Faculty / School', 'Department', 'Theses'], rows: rows,
        note: 'Faculty comes from the repository collection; department from the repository or the title page.')
  end

  CITED_NOTE = 'Citations from OpenAlex (CC0): a thesis is found in OpenAlex by matching its title and year, and the ' \
               'works OpenAlex records as citing it are counted. A lower bound: citations OpenAlex has not recorded, ' \
               'and theses not matched, are missing. Refreshed about weekly.'

  # Citations (FR-69): cited theses by institution (all institutions) and the most cited theses.
  def citation_sections(fq, f, words)
    k = self.class
    unless f.source
      facet = { inst: { type: 'terms', field: 'institution_ssim', limit: -1, mincount: 1,
                        facet: { found: { type: 'query', q: MATCHED },
                                 cited: { type: 'query', q: CITED, facet: { works: 'sum(cited_by_isi)' } } } } }
      buckets = k.solr({ fq: fq, 'json.facet': facet.to_json }, words).dig('facets', 'inst', 'buckets').to_a
      rows = buckets.map do |b|
        cited = b.dig('cited', 'count').to_i
        [b['val'], b['count'].to_i, b.dig('found', 'count').to_i, cited, k.pct(cited, b['count'].to_i),
         b.dig('cited', 'works').to_i]
      end.sort_by { |name, n, _, c, *| [-c, -n, name] }
      add(title: 'Cited theses by institution',
          headers: ['Institution', 'Theses', 'Found in OpenAlex', 'Cited', '% cited', 'Citing works'],
          rows: rows, total: true, note: CITED_NOTE)
    end
    rows = []
    k.each_doc(fq + [CITED], words, sort: 'cited_by_isi desc, year_isi desc, id asc', max: MOST_CITED) do |doc|
      h = ApiRecord.to_h(doc)
      rows << [h['title'], h['year'], h.dig('institution', 'name'), h.dig('cited_by', 'count'), h.dig('links', 'portal')]
    end
    add(title: 'Most cited theses', headers: ['Title', 'Year', 'Institution', 'Cited by', 'Link'],
        rows: rows.presence || [['No cited theses among these.', nil, nil, nil, nil]], kind: :listing,
        note: "The #{MOST_CITED} theses with the most citing works in OpenAlex. #{CITED_NOTE}")
  end

  # Usage (FR-61), for administrators: views and downloads since counting began, by institution, most viewed records.
  def usage_sections(f)
    first = UsageCount.minimum(:day)
    return add(title: 'Usage', headers: ['Note'], rows: [['Nothing counted yet.']], kind: :summary) unless first

    scope = UsageCount.where(event: %w[record_view pdf_download])
    name = f.institution_name
    scope = scope.where(institution: name) if name
    by = scope.group(:institution, :event).sum(:hits)
    insts = by.keys.map(&:first).uniq.sort_by { |i| -by[[i, 'record_view']].to_i }
    since = "Counted since #{self.class.date(first)} (UTC days), to #{self.class.date(Time.now.utc.to_date)}."
    add(title: 'Usage by institution', headers: ['Institution', 'Record views', 'PDF downloads'],
        rows: insts.map { |i| [i.presence || NOT_RECORDED, by[[i, 'record_view']].to_i, by[[i, 'pdf_download']].to_i] },
        total: true, kind: :usage,
        note: "#{since} A lower bound: PDF downloads only through the portal's Download link; crawlers, link previews and signed-in administrators are not counted.")
    top = scope.where(event: 'record_view').group(:record_id).order('sum_hits DESC').limit(20).sum(:hits).to_a
    titles = titles_for(top.map(&:first))
    add(title: 'Most viewed records', headers: %w[Title Views Link],
        rows: top.map { |id, n| [titles[id] || id, n, "#{ApiRecord::BASE}/theses/#{ThesisId.short(id)}"] }, kind: :usage)
    places = UsagePlace.where(event: %w[record_view pdf_download search]).group(:country).sum(:hits).sort_by { |_, n| -n }
    add(title: 'Readers by country (all institutions)', headers: ['Country', 'Views, downloads and searches'],
        rows: places.map { |c, n| [c.presence || 'Unknown', n] }, total: true, kind: :usage,
        note: 'Looked up offline from the reader\'s address, which is not kept (IP Geolocation by DB-IP, CC BY 4.0).')
  end

  def titles_for(ids)
    return {} if ids.empty?

    res = self.class.solr({ fq: ["id:(#{ids.map { |i| "\"#{self.class.esc(i)}\"" }.join(' OR ')})"],
                            rows: ids.size, fl: 'id,title_ssm' })
    res.dig('response', 'docs').to_a.to_h { |d| [d['id'], Array(d['title_ssm']).first] }
  end

  # ---- predefined report: supervisors ----------------------------------------------------------------------------

  def self.supervisors(params, list: true)
    f = Filters.new(params)
    fq, names = fqs(f)
    words = f.words
    r = new('supervisors', "ETDs by supervisor: #{f.institution_name || 'all institutions'}",
            'Theses and dissertations supervised, by degree level and years', f.describe(names))
    r.slug = f.slug
    total = count(fq, words)
    sfq = fq + ['supervisor_ssim:[* TO *]']
    with = count(sfq, words)
    levels = pivot('supervisor_ssim', 'degree_level_ssim', sfq, words)
    years = pivot('supervisor_ssim', 'year_ssim', sfq, words)
    insts = f.source ? {} : pivot('supervisor_ssim', 'institution_short_ssim', sfq, words)
    keep = names ? names.to_set : nil
    rows = levels.filter_map do |name, h|
      next if keep && !keep.include?(name)

      ys = years.fetch(name, {}).except(:total).keys.map(&:to_i).reject(&:zero?)
      known = LEVELS.sum { |l| h[l].to_i }
      row = [name, h[:total], *LEVELS.map { |l| h[l].to_i }, [h[:total] - known, 0].max, ys.min, ys.max]
      row << insts.fetch(name, {}).except(:total).keys.sort.join(', ') unless f.source
      row
    end.sort_by { |row| [-row[1], row[0]] }
    r.add(title: 'Summary', headers: %w[Measure Value], kind: :summary,
          rows: [['Distinct theses and dissertations', total],
                 ['With a supervisor recorded', "#{with} (#{pct(with, total)}%)"],
                 ['Supervisor names', rows.size],
                 ['Theses per supervisor name (median)', rows.empty? ? 0 : rows.map { |x| x[1] }.sort[rows.size / 2]]])
    headers = ['Supervisor', 'Theses', *LEVELS, NOT_RECORDED, 'First year', 'Last year']
    headers << 'Institution(s)' unless f.source
    r.add(title: 'Supervisors', headers: headers, rows: rows, chart: :bar_top,
          note: 'Names as written in the repository or on the title page; spelling variants of one person (initials, titles) are not merged, so one person may appear on more than one row. A thesis with two supervisors counts for each.')
    r.supervisor_listing(sfq, words, keep) if list
    r.notes.push(*standard_notes)
    r
  end

  def supervisor_listing(fq, words, keep)
    rows = []
    self.class.each_doc(fq, words, sort: 'year_isi desc, id asc') do |doc|
      h = ApiRecord.to_h(doc)
      how = h.dig('derived', 'supervisors') ? 'Portal (title page)' : 'Repository'
      h['supervisors'].each do |s|
        next if keep && !keep.include?(s)

        rows << [s, h['year'], h['title'], h['authors'].join('; '), h['degree_level'], h['department'].join('; '),
                 h.dig('institution', 'name'), how, h.dig('links', 'portal')]
      end
    end
    rows.sort_by! { |x| [x[0].to_s.downcase, -x[1].to_i] }
    add(title: 'Theses by supervisor', kind: :listing, rows: rows,
        headers: ['Supervisor', 'Year', 'Title', 'Author(s)', 'Degree level', 'Department', 'Institution',
                  'Supervisor from', 'Portal link'])
  end

  # ---- custom report ---------------------------------------------------------------------------------------------

  def self.custom(params, list_max: LIST_MAX)
    f = Filters.new(params)
    fq, names = fqs(f)
    words = f.words
    group = GROUPS.key?(params[:group].to_s) ? params[:group].to_s : nil
    then_by = GROUPS.key?(params[:then_by].to_s) && params[:then_by].to_s != group ? params[:then_by].to_s : nil
    cols = Array(params[:columns]).map(&:to_s) & COLUMNS.keys
    cols = DEFAULT_COLUMNS if cols.empty?
    listing = params[:list].to_s == '1'
    r = new('custom', params[:report_title].to_s.strip.first(120).presence || 'Custom ETD report',
            [("Grouped by #{GROUPS[group].first.downcase}" if group), ("then by #{GROUPS[then_by].first.downcase}" if then_by)].compact.join(', ').presence || 'Selected theses',
            f.describe(names))
    r.slug = f.slug
    total = count(fq, words)
    r.add(title: 'Summary', headers: %w[Measure Value], kind: :summary,
          rows: [['Distinct theses and dissertations matching the filters', total]])
    r.custom_groups(fq, words, group, then_by, total) if group
    r.custom_listing(fq, words, cols, list_max) if listing || !group
    r.notes.push(*standard_notes)
    r
  end

  MAX_COLUMNS = 30

  def custom_groups(fq, words, group, then_by, total)
    k = self.class
    glabel, gfield = GROUPS[group]
    sorter = ->(rows) { group == 'year' ? k.year_sorted(rows) : rows }
    unless then_by
      rows = sorter.call(k.facet(gfield, fq, words)).map { |v, n| [k.label(v), n, k.pct(n, total)] }
      return add(title: "By #{glabel.downcase}", headers: [glabel, 'Theses', '% of all'], rows: rows, total: true,
                 chart: group == 'year' ? :column : (rows.size > 25 ? :bar_top : :bar))
    end

    tlabel, tfield = GROUPS[then_by]
    cols = k.facet(tfield, fq, words, missing: false)
    cols = then_by == 'year' ? k.year_sorted(cols) : cols
    other = cols.size > MAX_COLUMNS
    shown = cols.first(MAX_COLUMNS).map(&:first)
    shown.sort_by!(&:to_i) if then_by == 'year'
    pv = k.pivot(gfield, tfield, fq, words)
    g_rows = sorter.call(k.facet(gfield, fq, words, missing: false))
    rows = g_rows.map do |v, n|
      h = pv.fetch(v, {})
      vals = shown.map { |c| h[c].to_i }
      rest = h.except(:total).sum { |c, m| shown.include?(c) ? 0 : m }
      [k.label(v), *vals, *([rest] if other), n]
    end
    missing = k.count(fq + ["-#{gfield}:[* TO *]"], words)
    rows << [NOT_RECORDED, *Array.new(shown.size + (other ? 1 : 0), nil), missing] if missing.positive?
    add(title: "By #{glabel.downcase} and #{tlabel.downcase}", headers: [glabel, *shown, *('Other' if other), 'Total'],
        rows: rows, total: true,
        note: "Columns: #{tlabel.downcase}#{" (the #{MAX_COLUMNS} most frequent; the rest under Other)" if other}. Total is the number of theses in the row.")
  end

  def custom_listing(fq, words, cols, max = LIST_MAX)
    rows = []
    self.class.each_doc(fq, words, max: max) do |doc|
      h = ApiRecord.to_h(doc)
      rows << cols.map { |c| self.class.value(h, doc, c) }
    end
    note = rows.size >= max ? "The first #{max} theses (newest first); narrow the filters for the rest." : 'Newest first.'
    add(title: 'Theses', headers: cols.map { |c| COLUMNS[c] }, rows: rows, kind: :listing, note: note)
  end
end
