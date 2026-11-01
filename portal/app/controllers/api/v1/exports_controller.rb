# frozen_string_literal: true

require 'csv'

module Api
  module V1
    # GET /api/v1/export.csv and /api/v1/export.jsonl (FR-46): every record, rebuilt at most every 6 hours.
    class ExportsController < BaseController
      DIR = Rails.root.join('tmp', 'api_export')
      MAX_AGE = 6.hours
      rate_limit to: 20, within: 1.hour, name: 'export',
                 with: -> { error(429, 'Too many requests', 'At most 20 exports an hour; the file changes at most every 6 hours.') }

      def show
        fmt = params[:format].to_s
        return error(400, 'Bad request', 'Use /api/v1/export.csv or /api/v1/export.jsonl') unless %w[csv jsonl].include?(fmt)

        path = ensure_file(fmt)
        response.headers['Last-Modified'] = File.mtime(path).httpdate
        send_file path, type: fmt == 'csv' ? 'text/csv; charset=utf-8' : 'application/x-ndjson; charset=utf-8',
                        filename: "netd-records-#{File.mtime(path).utc.strftime('%Y-%m-%d')}.#{fmt}", disposition: 'attachment'
      end

      private

      def ensure_file(fmt)
        FileUtils.mkdir_p(DIR)
        path = DIR.join("records.#{fmt}")
        return path if fresh?(path)

        File.open(DIR.join('build.lock'), File::RDWR | File::CREAT) do |lock|
          lock.flock(File::LOCK_EX)
          return path if fresh?(path) # built by another request while we waited

          tmp = DIR.join("records.#{fmt}.tmp")
          File.open(tmp, 'w') do |out|
            out.write(CSV.generate_line(ApiRecord::CSV_COLUMNS)) if fmt == 'csv'
            each_doc do |d|
              out.write(fmt == 'csv' ? CSV.generate_line(ApiRecord.to_csv_row(d)) : "#{ApiRecord.to_h(d).to_json}\n")
            end
          end
          File.rename(tmp, path)
        end
        path
      end

      def fresh?(path) = File.exist?(path) && File.mtime(path) > MAX_AGE.ago

      def each_doc
        cursor = '*'
        loop do
          res = solr(q: '*:*', defType: 'lucene', sort: 'id asc', rows: 500, cursorMark: cursor, fl: ApiRecord::FIELDS)
          res['response']['docs'].each { |d| yield d }
          break if res['nextCursorMark'] == cursor

          cursor = res['nextCursorMark']
        end
      end
    end
  end
end
