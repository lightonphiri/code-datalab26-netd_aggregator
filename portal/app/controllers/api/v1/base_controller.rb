# frozen_string_literal: true

module Api
  module V1
    # Read-only public REST API (SRS EI-6, FR-42 to FR-46). JSON only, no key, CORS open, rate-limited per address.
    class BaseController < ActionController::API
      LIMIT = 120 # requests per minute per address
      rate_limit to: LIMIT, within: 1.minute, with: -> { error(429, 'Too many requests', "At most #{LIMIT} requests a minute; please slow down.") }

      before_action :cors
      rescue_from ActionController::BadRequest, ArgumentError do |e|
        error(400, 'Bad request', e.message)
      end
      rescue_from RSolr::Error::ConnectionRefused, RSolr::Error::Http, Errno::ECONNREFUSED do
        error(503, 'Service unavailable', 'The search index is not answering; please try again shortly.')
      end

      def preflight = head(:no_content)

      def not_found = error(404, 'Not found', "No API endpoint at #{request.path}. See https://netd.ac.zm/api/v1/openapi.yaml")

      private

      def cors
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Accept, Content-Type'
        response.headers['Access-Control-Max-Age'] = '86400'
      end

      def error(status, title, detail)
        render json: { 'error' => { 'status' => status, 'title' => title, 'detail' => detail } }, status: status
      end

      def solr(params)
        defaults = { wt: 'json', facet: false, spellcheck: false }
        Blacklight.default_index.connection.get('select', params: defaults.merge(params))
      end

      # Counts are of theses, not copies: duplicates listed under a main record are left out (FR-19).
      UNIQUE = '-duplicate_of_ssi:[* TO *]'

      def facet(field, extra = {})
        extra = extra.merge(fq: [*extra[:fq], UNIQUE])
        res = solr(extra.merge(q: '*:*', defType: 'lucene', rows: 0, facet: true, 'facet.field': field,
                               'facet.limit': -1, 'facet.mincount': 1))
        [res.dig('facet_counts', 'facet_fields', field).to_a.each_slice(2).to_h, res['response']['numFound']]
      end

      def cache(key, &)
        Rails.cache.fetch("api/v1/#{key}", expires_in: 10.minutes, &)
      end
    end
  end
end
