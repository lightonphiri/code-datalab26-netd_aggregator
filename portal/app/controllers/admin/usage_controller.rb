# frozen_string_literal: true

module Admin
  # Usage analytics (SRS FR-61): aggregate counts kept by the portal itself (no third-party trackers, no IP
  # addresses). Days are UTC. ?days=7|30|90|365; ?format=csv downloads the daily counts of the period.
  class UsageController < BaseController
    PERIODS = [7, 30, 90, 365].freeze

    def index
      @days = PERIODS.include?(params[:days].to_i) ? params[:days].to_i : 30
      scope = UsageCount.since(@days)
      respond_to do |format|
        format.html { summarise(scope) }
        format.csv do
          rows = scope.group(:day, :event, :institution).order(:day, :event, :institution).sum(:hits)
          csv = +"day,event,institution,count\n"
          rows.each { |(day, ev, inst), n| csv << [day, ev, inst, n].map { |v| v.to_s.include?(',') ? "\"#{v}\"" : v }.join(',') << "\n" }
          send_data csv, filename: "netd-usage-#{Time.now.utc.to_date}-#{@days}d.csv", type: 'text/csv'
        end
      end
    end

    private

    def summarise(scope)
      @first_day = UsageCount.minimum(:day)
      @totals = scope.group(:event).sum(:hits)
      @daily = scope.group(:day, :event).sum(:hits)
      @dates = (Time.now.utc.to_date - (@days - 1))..Time.now.utc.to_date
      @by_inst = scope.where(event: %w[record_view pdf_download]).group(:institution, :event).sum(:hits)
      @endpoints = scope.where(event: %w[api oai]).group(:event, :record_id).sum(:hits).sort_by { |_, n| -n }
      @top_views = top(scope, 'record_view')
      @top_pdfs = top(scope, 'pdf_download')
      ids = (@top_views + @top_pdfs).map(&:first).uniq
      @titles = titles(ids)
    end

    def top(scope, event) = scope.where(event: event).group(:record_id).order('sum_hits DESC').limit(20).sum(:hits).to_a

    def titles(ids)
      return {} if ids.empty?

      q = "id:(#{ids.map { |i| "\"#{i.gsub(/[^A-Za-z0-9_-]/, '')}\"" }.join(' OR ')})"
      res = Blacklight.default_index.connection.get('select', params: { q: q, fl: 'id,title_tsim', rows: ids.size, wt: 'json' })
      res.dig('response', 'docs').to_a.to_h { |d| [d['id'], Array(d['title_tsim']).first] }
    rescue StandardError
      {}
    end
  end
end
