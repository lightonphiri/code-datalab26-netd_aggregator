# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/records (search, FR-42) and GET /api/v1/records/{id} (FR-43).
    class RecordsController < BaseController
      PER_PAGE = 20
      MAX_PER_PAGE = 100
      MAX_RESULTS = 10_000 # deeper paging: use /api/v1/export or OAI-PMH
      FIELDS = %w[all title author supervisor subject].freeze
      SORTS = {
        'relevance' => 'score desc, year_isi desc, id asc', 'newest' => 'year_isi desc, title_ssort asc, id asc',
        'oldest' => 'year_isi asc, title_ssort asc, id asc', 'title' => 'title_ssort asc, id asc',
        'updated' => 'updated_dtsi desc, id asc', 'added' => 'added_dtsi desc, id asc'
      }.freeze
      EXACT = { 'faculty' => 'faculty_ssim', 'department' => 'department_ssim', 'discipline' => 'discipline_ssim',
                'degree' => 'degree_ssim', 'subject_exact' => 'subject_ssim', 'supervisor_exact' => 'supervisor_ssim' }.freeze
      LEVELS = { 'masters' => 'Masters', 'doctoral' => 'Doctoral', 'postgraduate_diploma' => 'Postgraduate Diploma' }.freeze
      KNOWN = %w[q field institution level year full_text updated_since sort page per_page] + EXACT.keys

      def index
        unknown = request.query_parameters.keys - KNOWN
        raise ArgumentError, "Unknown parameter(s): #{unknown.join(', ')}" if unknown.any?

        page = int_param(:page, 1, 1..)
        per = int_param(:per_page, PER_PAGE, 1..MAX_PER_PAGE)
        start = (page - 1) * per
        raise ArgumentError, "page × per_page may not exceed #{MAX_RESULTS}; use /api/v1/export for everything" if start + per > MAX_RESULTS

        sort = params[:sort].presence || (params[:q].present? ? 'relevance' : 'newest')
        raise ArgumentError, "sort must be one of #{SORTS.keys.join(', ')}" unless SORTS.key?(sort)

        res = solr(query.merge(fq: filters, sort: SORTS[sort], start: start, rows: per, fl: ApiRecord::FIELDS))
        total = res['response']['numFound']
        pages = (total.to_f / per).ceil
        render json: { 'data' => res['response']['docs'].map { |d| ApiRecord.to_h(d) },
                       'meta' => { 'total' => total, 'page' => page, 'per_page' => per, 'pages' => pages, 'sort' => sort },
                       'links' => links(page, pages) }
      end

      def show
        id = params[:id].to_s
        raise ArgumentError, 'Invalid record id' unless id.match?(/\A[A-Za-z0-9_-]{1,200}\z/)

        doc = solr(q: "{!term f=id}#{id}", defType: 'lucene', rows: 1, fl: ApiRecord::FIELDS)['response']['docs'].first
        return error(404, 'Not found', "No record with id #{id}") unless doc

        render json: { 'data' => ApiRecord.to_h(doc) }
      end

      private

      def int_param(name, default, range)
        return default if params[name].blank?
        raise ArgumentError, "#{name} must be a whole number" unless params[name].to_s.match?(/\A\d+\z/)

        v = params[name].to_i
        raise ArgumentError, "#{name} is out of range (#{range.begin}#{"–#{range.end}" if range.end})" unless range.cover?(v)

        v
      end

      # Keyword search with the same Solr settings as the portal's search box (edismax, ETD field weights).
      def query
        q = params[:q].to_s.strip
        return { q: '*:*', defType: 'lucene' } if q.empty?

        field = params[:field].presence || 'all'
        raise ArgumentError, "field must be one of #{FIELDS.join(', ')}" unless FIELDS.include?(field)

        p = { q: q, defType: 'edismax' }
        p.merge!(qf: "${#{field}_qf}", pf: "${#{field}_pf}") unless field == 'all'
        p
      end

      def filters
        fq = []
        if params[:institution].present?
          ids = params[:institution].to_s.split(',').map(&:strip)
          bad = ids.grep_v(/\A[a-z][a-z0-9]{1,15}\z/)
          raise ArgumentError, "Invalid institution id(s): #{bad.join(', ')} (see /api/v1/institutions)" if bad.any?

          fq << "{!terms f=source_ssi}#{ids.join(',')}"
        end
        if params[:level].present?
          raise ArgumentError, 'level must be masters, doctoral or postgraduate_diploma' unless LEVELS.key?(params[:level])

          fq << "{!term f=degree_level_ssim}#{LEVELS[params[:level]]}"
        end
        if params[:year].present?
          m = params[:year].to_s.match(/\A(\d{4})(?:-(\d{4}))?\z/) or raise ArgumentError, 'year must be YYYY or YYYY-YYYY'
          fq << "year_isi:[#{m[1]} TO #{m[2] || m[1]}]"
        end
        if params[:full_text].present?
          raise ArgumentError, 'full_text must be true or false' unless %w[true false].include?(params[:full_text])

          fq << "#{'-' if params[:full_text] == 'false'}full_text_ssim:\"PDF available\""
        end
        if params[:updated_since].present?
          v = params[:updated_since].to_s
          t = Time.iso8601(v.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? "#{v}T00:00:00Z" : v) rescue raise(ArgumentError, 'updated_since must be YYYY-MM-DD or YYYY-MM-DDThh:mm:ssZ')
          fq << "updated_dtsi:[#{t.utc.strftime('%Y-%m-%dT%H:%M:%SZ')} TO *]"
        end
        EXACT.each { |p, f| fq << "{!term f=#{f}}#{params[p]}" if params[p].present? }
        fq
      end

      def links(page, pages)
        url = ->(p) { "#{ApiRecord::BASE}/api/v1/records?#{request.query_parameters.merge('page' => p).to_query}" }
        { 'self' => url[page], 'first' => url[1], 'last' => url[[pages, 1].max],
          'prev' => page > 1 ? url[page - 1] : nil, 'next' => page < pages ? url[page + 1] : nil }
      end
    end
  end
end
