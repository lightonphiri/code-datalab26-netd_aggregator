# frozen_string_literal: true

# Discovery configuration for the Zambia National ETD Portal (netd.ac.zm).
# Field names follow the harvester's Solr mapping (harvester/netd/index.py).
class CatalogController < ApplicationController
  include Blacklight::Catalog
  include UsageCounting

  # One address per thesis (FR-68): /theses/unza-123456789-9150 redirects permanently to /theses/unza-9150.
  before_action :canonical_thesis_address, only: %i[show pdf cite]

  configure_blacklight do |config|
    config.header_component = NetdHeaderComponent
    # No search-history row for crawlers (one crawler made 162,594 requests in a morning, November 2, 2026)
    config.crawler_detector = ->(req) { req.user_agent.blank? || req.user_agent.match?(UsageCounting::BOT) }
    # 10 results per page as on Google Scholar; "Show" menu offers 20, 50 and 100
    config.default_solr_params = { rows: 10 }
    config.default_per_page = 10
    config.per_page = [10, 20, 50, 100]

    # ---- results list --------------------------------------------------
    config.index.title_field = 'title_tsim'
    config.index.document_component = EtdResultComponent
    # (no index fields: the result line is laid out by EtdResultComponent, Academic Commons style)

    # ---- record page ----------------------------------------------------
    config.show.title_field = 'title_tsim'
    config.show.document_component = EtdShowComponent
    config.add_show_field 'author_tsim', label: 'Author', link_to_facet: 'author_ssim'
    config.add_show_field 'supervisor_ssim', label: 'Supervisor', link_to_facet: 'supervisor_ssim'
    config.add_show_field 'institution_ssim', label: 'Institution', link_to_facet: true
    config.add_show_field 'faculty_tsim', label: 'Faculty / School', link_to_facet: 'faculty_ssim'
    config.add_show_field 'department_tsim', label: 'Department', link_to_facet: 'department_ssim'
    config.add_show_field 'degree_level_ssim', label: 'Degree level', link_to_facet: true
    config.add_show_field 'degree_ssim', label: 'Degree', link_to_facet: true
    config.add_show_field 'discipline_tsim', label: 'Programme / Discipline', link_to_facet: 'discipline_ssim'
    config.add_show_field 'year_ssim', label: 'Year', link_to_facet: true
    config.add_show_field 'subject_tsim', label: 'Keywords (from the repository)', link_to_facet: 'subject_ssim', separator_options: { words_connector: '; ', last_word_connector: '; ', two_words_connector: '; ' }
    config.add_show_field 'language_ssim', label: 'Language'
    config.add_show_field 'abstract_tesim', label: 'Abstract'

    # ---- facets ----------------------------------------------------------
    config.add_facet_field 'institution_ssim', label: 'Institution', limit: 10, collapse: false,
                                              component: InstitutionFacetComponent
    config.add_facet_field 'full_text_ssim', label: 'Full text', collapse: false
    config.add_facet_field 'degree_level_ssim', label: 'Degree level', collapse: false
    # Field of study: OpenAlex Topics, assigned to every record (FR-55); the main subject facets
    config.add_facet_field 'fos_domain_ssim', label: 'Research domain', limit: 4, collapse: false
    config.add_facet_field 'fos_field_ssim', label: 'Field of study', limit: 10, collapse: false
    config.add_facet_field 'fos_subfield_ssim', label: 'Subfield', limit: 10
    config.add_facet_field 'faculty_ssim', label: 'Faculty / School', limit: 10
    config.add_facet_field 'department_ssim', label: 'Department', limit: 10
    config.add_facet_field 'discipline_ssim', label: 'Programme / Discipline', limit: 10
    config.add_facet_field 'degree_ssim', label: 'Degree', limit: 10
    config.add_facet_field 'supervisor_ssim', label: 'Supervisor', limit: 10
    config.add_facet_field 'subject_ssim', label: 'Keywords (from the repository)', limit: 15
    config.add_facet_field 'year_ssim', label: 'Year', limit: 200, sort: 'index', component: YearFacetComponent
    config.add_facet_field 'author_ssim', label: 'Author', show: false
    config.add_facet_fields_to_solr_request!

    # ---- search fields -----------------------------------------------------
    config.add_search_field 'all_fields', label: 'All fields'
    { 'title' => 'Title', 'author' => 'Author', 'supervisor' => 'Supervisor', 'subject' => 'Subject' }.each do |key, label|
      config.add_search_field(key, label: label) do |field|
        field.solr_parameters = { 'spellcheck.dictionary': key == 'supervisor' ? 'default' : key,
                                  qf: "${#{key}_qf}", pf: "${#{key}_pf}" }
      end
    end

    # ---- sorting -------------------------------------------------------------
    # Sort control next to the result count (the default tools were dropped when this file was rewritten)
    config.add_results_collection_tool(:sort_widget)
    config.add_results_collection_tool(:per_page_widget)
    config.add_results_collection_tool(:follow_search, partial: 'follow_search_link')  # feeds for a search (FR-60)

    # Sort options as on Columbia's Academic Commons (FR-22)
    config.add_sort_field 'relevance', sort: 'score desc, year_isi desc, title_ssort asc', label: 'Best Match'
    config.add_sort_field 'latest', sort: 'year_isi desc, title_ssort asc', label: 'Published Latest'
    config.add_sort_field 'earliest', sort: 'year_isi asc, title_ssort asc', label: 'Published Earliest'
    config.add_sort_field 'title_az', sort: 'title_ssort asc, year_isi desc', label: 'Title A-Z'
    config.add_sort_field 'title_za', sort: 'title_ssort desc, year_isi desc', label: 'Title Z-A'
    config.add_sort_field 'added', sort: 'added_dtsi desc, title_ssort asc', label: 'Newest Additions'  # FR-60

    config.spell_max = 5
    config.autocomplete_enabled = false
  end

  # Usage analytics (FR-61): home page visits, searches (first results page only) and record page views.
  def index
    super
    return unless html_page?

    if has_search_parameters?
      if params[:page].to_i <= 1
        count_usage('search')
        count_facets
      end
    else
      count_usage('home')
    end
  end

  def show
    super
    return unless html_page? && @document

    count_usage('record_view', record_id: @document.id, institution: Array(@document['institution_ssim']).first)
    @usage = UsageCount.where(record_id: @document.id, event: %w[record_view pdf_download]).group(:event).sum(:hits)
    @similar = similar_theses(@document.id)
  end

  # GET /sitemap.xml: every listed record page (other copies of duplicates left out), for Google and Google Scholar
  # (FR-66). Cached for a day; not counted as usage.
  def sitemap
    xml = Rails.cache.fetch('netd/sitemap', expires_in: 1.day) do
      conn = Blacklight.default_index.connection
      ids, start = [], 0
      loop do
        r = conn.get('select', params: { q: '*:*', fq: '-duplicate_of_ssi:[* TO *]', fl: 'id,year_ssim', rows: 2000,
                                         start: start, sort: 'id asc', facet: false, spellcheck: false, wt: 'json' })
        docs = r.dig('response', 'docs') || []
        ids.concat(docs.map { |d| d['id'] })
        start += docs.size
        break if docs.size < 2000
      end
      urls = [root_url, browse_url] + ids.map { |id| solr_document_url(ThesisId.short(id)) }
      %(<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n) +
        urls.map { |u| "<url><loc>#{ERB::Util.html_escape(u)}</loc></url>" }.join("\n") + "\n</urlset>\n"
    end
    render xml: xml
  end

  # GET /theses/:id/pdf(?file=n): counts the download, then sends the reader to the repository's own copy. Only a
  # link stored in the record is used (no open redirect).
  def pdf
    doc = retrieve_document(params[:id].to_s)
    doc = doc.last if doc.is_a?(Array)
    files = Array(doc['files_ssm']).filter_map { |j| JSON.parse(j) rescue nil }
    url = if params[:file].present?
            files[params[:file].to_i]&.dig('url')
          else
            Array(doc['pdf_url_ssm']).first.presence || files.first&.dig('url')
          end
    return head(:not_found) unless url.to_s.match?(%r{\Ahttps?://}i)

    count_usage('pdf_download', record_id: doc.id, institution: Array(doc['institution_ssim']).first)
    response.headers['X-Robots-Tag'] = 'noindex'
    redirect_to url, allow_other_host: true, status: :found
  end



  # GET /theses/:id/cite?style=apa (an HTML fragment for the "How to cite" panel) and /theses/:id/cite.ris or
  # .bib (downloads for reference managers). SRS FR-65. Not counted as usage; kept out of search engines.
  def cite
    doc = retrieve_document(params[:id].to_s)
    doc = doc.last if doc.is_a?(Array)
    c = Citation.new(doc, solr_document_url(doc))
    response.headers['X-Robots-Tag'] = 'noindex'
    case params[:format]
    when 'ris' then send_data c.ris, filename: "#{doc.id}.ris", type: 'application/x-research-info-systems'
    when 'bib' then send_data c.bibtex, filename: "#{doc.id}.bib", type: 'application/x-bibtex'
    else render html: helpers.citation_html(c, params[:style].to_s), layout: false
    end
  end

  private

    # Address id (short or record id) -> the record (FR-68). Used by show (through Blacklight), pdf and cite.
    def retrieve_document(id)
      super(ThesisId.resolve(id) || id)
    end

    def canonical_thesis_address
      given = params[:id].to_s
      short = ThesisId.short(given)
      return if short == given

      q = request.query_string.presence
      redirect_to "#{request.path.sub("/theses/#{given}", "/theses/#{short}")}#{"?#{q}" if q}", status: :moved_permanently
    end

    def html_page? = response.successful? && response.media_type.to_s == 'text/html'

    # "Similar theses" (FR-67): Solr MoreLikeThis on title, abstract and keywords; other copies of duplicates left out.
    def similar_theses(id)
      r = Blacklight.default_index.connection.get('select', params: {
        q: "id:#{RSolr.solr_escape(id)}", rows: 1, fl: 'id,title_tsim,year_ssim,institution_short_ssim,duplicate_of_ssi',
        mlt: true, 'mlt.fl' => 'title_tsim,abstract_tesim,subject_tsim', 'mlt.mintf' => 1, 'mlt.mindf' => 2,
        'mlt.count' => 10, facet: false, spellcheck: false, wt: 'json'
      })
      (r.dig('moreLikeThis', id, 'docs') || []).reject { |d| d['duplicate_of_ssi'] }.first(5)
    rescue StandardError => e
      Rails.logger.warn("similar_theses #{id}: #{e.class}")
      []
    end

  # Popular searches (FR-61): facet values chosen on a first results page that found records. Only configured facet
  # fields, at most 10 values per search; nothing typed by the reader is stored.
  def count_facets
    return unless human_visit? && @response && @response.total.to_i.positive? && params[:f].respond_to?(:to_unsafe_h)

    fields = blacklight_config.facet_fields.keys
    params[:f].to_unsafe_h.flat_map { |field, vals| fields.include?(field.to_s) ? Array(vals).map { |v| [field, v] } : [] }
                                   .first(10).each { |field, v| UsageFacet.bump(field, v) }
  end

end
