# frozen_string_literal: true

module Admin
  # Overview (FR-37): sources and their latest harvest, records in the store and the search index, open reports.
  class DashboardController < BaseController
    def index
      @sources = Harvester.sources
      @status = Harvester.status
      @indexed = solr_counts
      @running = Harvester.running?
      @open_reports = ProblemReport.where(status: 'open').count
      @events = AdminEvent.includes(:user).order(created_at: :desc).limit(15)
      @repo_check = Harvester.repository_check
    end

    def run
      src = Harvester.source(params[:id])
      return redirect_to(admin_root_path, alert: 'Unknown source.') unless src

      if Harvester.start_run(src['id'])
        audit('harvest_started', src['id'])
        redirect_to admin_source_path(src['id']), notice: "Harvest of #{src['name']} started. Refresh this page to follow it."
      else
        redirect_to admin_root_path, alert: 'A harvest is already running. Try again when it has finished.'
      end
    end

    def source
      @source = Harvester.source(params[:id]) or return redirect_to(admin_root_path, alert: 'Unknown source.')
      @runs = Harvester.recent_runs(@source['id'])
      @excluded = Harvester.excluded(@source['id'])
      @log = Harvester.run_log(@source['id'])
      @running = Harvester.running?
    end

    private

    def solr_counts
      res = Blacklight.default_index.connection.get('select', params: { q: '*:*', rows: 0, facet: true,
                                                                        'facet.field': 'source_ssi', 'facet.limit': -1 })
      f = res.dig('facet_counts', 'facet_fields', 'source_ssi') || []
      f.each_slice(2).to_h
    rescue StandardError
      {}
    end
  end
end
