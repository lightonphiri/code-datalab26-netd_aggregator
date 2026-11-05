# frozen_string_literal: true

module Admin
  # Duplicate ETDs (FR-19): theses deposited more than once. The portal lists each once, under a main record chosen
  # automatically (PDF, then completeness, then the later deposit). An admin can mark a record as not a duplicate, or
  # choose a group's main record; both are stored as "_duplicate" corrections, kept across re-harvests.
  class DuplicatesController < BaseController
    def index
      @groups = Harvester.duplicate_groups
      @decided = Harvester.duplicate_decisions
      @running = Harvester.running?
    end

    # POST /admin/duplicates/:id  decision=distinct|primary
    def decide
      id = params[:id].to_s
      decision = params[:decision].to_s
      return redirect_to(admin_duplicates_path, alert: flash_text('unknown_decision')) unless %w[distinct primary].include?(decision)

      record = Harvester.record(id) or return redirect_to(admin_duplicates_path, alert: flash_text('no_record', id: id))
      note = decision == 'distinct' ? 'not a duplicate' : 'main record of its group'
      ok, out = Harvester.correct(id, '_duplicate', [decision], by: current_admin.email_address, note: note)
      return redirect_to(admin_duplicates_path, alert: flash_text('decision_not_saved', detail: out.lines.last)) unless ok

      audit(decision == 'distinct' ? 'duplicate_rejected' : 'duplicate_primary_chosen', "record:#{id}", note)
      started = Harvester.start_reprocess(record['source'])
      redirect_to admin_duplicates_path, notice: "#{flash_text(decision == 'distinct' ? 'duplicate_distinct' : 'duplicate_primary', id: id)} " +
        flash_text(started ? 'processing_started' : 'applies_later')
    end
  end
end
