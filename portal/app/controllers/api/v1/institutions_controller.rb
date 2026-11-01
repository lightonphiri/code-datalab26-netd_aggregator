# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/institutions (FR-44): every HEA-listed institution with its record count and harvest status.
    class InstitutionsController < BaseController
      def index
        data = cache('institutions') do
          counts, = facet('institution_ssim')
          sources = Harvester.sources.to_h { |s| [s['name'], s] }
          runs = Harvester.status[:runs]
          InstitutionRegistry.all.map do |i|
            src = sources[i[:name]]
            run = src && runs[src['id']]
            { 'id' => src&.dig('id'), 'name' => i[:name], 'short_name' => src&.dig('short_name'),
              'postgraduate_levels' => Array(i[:levels]), 'records' => counts[i[:name]] || 0,
              'status' => src ? 'harvested' : i[:status], 'repository' => i[:repository],
              'harvest_method' => src && (src['loader'] || 'oai-pmh'),
              'last_harvest' => run && Time.at(run['started_at']).utc.iso8601,
              'records_url' => src && "#{ApiRecord::BASE}/api/v1/records?institution=#{src['id']}" }
          end.sort_by { |h| [-h['records'], h['name']] }
        end
        render json: { 'data' => data, 'meta' => { 'total' => data.size, 'with_records' => data.count { |h| h['records'].positive? },
                                                   'source' => 'Higher Education Authority, https://www.hea.org.zm' } }
      end
    end
  end
end
