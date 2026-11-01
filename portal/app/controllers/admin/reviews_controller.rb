# frozen_string_literal: true

module Admin
  # Degree-level review (FR-52): records a model judged to be below postgraduate level, but not confidently enough
  # to exclude them automatically. Confirming excludes the record (FR-47); keeping it records that it is in scope.
  # Either decision is stored as a "_scope" correction, so it survives re-harvests and the model is not asked again.
  class ReviewsController < BaseController
    def index
      @status = params[:status] == 'decided' ? 'decided' : 'pending'
      @items = Harvester.level_review(@status)
      @running = Harvester.running?
    end

    # POST /admin/review/:id  decision=exclude|include
    def decide
      id = params[:id].to_s
      decision = params[:decision].to_s
      return redirect_to(admin_reviews_path, alert: 'Unknown decision.') unless %w[exclude include].include?(decision)

      note = params[:note].to_s.strip.presence ||
             (decision == 'exclude' ? 'confirmed below postgraduate level' : 'confirmed postgraduate')
      ok, out = Harvester.correct(id, '_scope', [decision], by: current_admin.email_address, note: note)
      return redirect_to(admin_reviews_path, alert: "Decision not saved: #{out.lines.last}") unless ok

      audit(decision == 'exclude' ? 'level_review_excluded' : 'level_review_kept', "record:#{id}", note)
      redirect_to admin_reviews_path, notice: "#{id}: #{decision == 'exclude' ? 'will be excluded' : 'kept in the portal'} " \
                                              'when its source is next processed.'
    end
  end
end
