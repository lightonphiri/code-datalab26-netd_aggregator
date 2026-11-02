# frozen_string_literal: true

module Admin
  # Usage analytics (SRS FR-61): aggregate counts kept by the portal itself (no third-party trackers, no IP
  # addresses). Days are UTC. ?days=7|30|90|365; ?format=csv downloads the daily counts of the period
  # (?table=places: country and approximate city; ?table=facets: facet values chosen).
  class UsageController < BaseController
    PERIODS = [7, 30, 90, 365].freeze

    def index
      @days = PERIODS.include?(params[:days].to_i) ? params[:days].to_i : 30
      scope = UsageCount.since(@days)
      respond_to do |format|
        format.html { summarise(scope) }
        format.csv do
          kind, header, rows = csv_rows(scope)
          csv = +"#{header}\n"
          rows.each { |keys, n| csv << [*keys, n].map { |v| v.to_s.match?(/[,"]/) ? "\"#{v.to_s.gsub('"', '""')}\"" : v }.join(',') << "\n" }
          send_data csv, filename: "netd-usage#{kind}-#{Time.now.utc.to_date}-#{@days}d.csv", type: 'text/csv'
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
      places_and_facets
    end

    # ?table=places (country, approximate city) or ?table=facets (facet values chosen); default: events.
    def csv_rows(scope)
      case params[:table]
      when 'places'
        ['-places', 'day,event,country_code,country,city,count',
         UsagePlace.since(@days).group(:day, :event, :country_code, :country, :city).order(:day, :event).sum(:hits)]
      when 'facets'
        ['-facets', 'day,facet,value,count', UsageFacet.since(@days).group(:day, :field, :value).order(:day, :field).sum(:hits)]
      else
        ['', 'day,event,institution,count', scope.group(:day, :event, :institution).order(:day, :event, :institution).sum(:hits)]
      end
    end

    def places_and_facets
      places = UsagePlace.since(@days).where(event: %w[record_view pdf_download search])
      @countries = places.group(:country, :event).sum(:hits)
      @cities = places.where.not(city: '').group(:city, :country).sum(:hits).sort_by { |_, n| -n }.first(20)
      labels = blacklight_facet_labels
      @facets = UsageFacet.since(@days).group(:field, :value).sum(:hits)
                          .group_by { |(f, _), _| f }.to_h { |f, rows| [labels[f] || f, rows.sort_by { |_, n| -n }.first(10)] }
      @geo_ready = File.exist?(GeoLookup::PATH)
    end

    def blacklight_facet_labels
      CatalogController.blacklight_config.facet_fields.to_h { |k, v| [k.to_s, (v.label.presence || k).to_s] }
    rescue StandardError
      {}
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
