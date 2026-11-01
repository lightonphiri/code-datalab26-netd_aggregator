# frozen_string_literal: true

module Admin
  # Manual corrections (FR-51): look up a record, see where each value came from (harvested, derived by a model,
  # corrected), and correct or clear values. Corrections override harvested and predicted values, are kept across
  # re-harvests and take effect when the record's source is next processed (nightly, or "Apply now").
  class RecordsController < BaseController
    before_action :load_record, except: :lookup

    # GET /admin/records?id=... (a record id or a portal record URL)
    def lookup
      id = params[:id].to_s.strip.split('/').last.to_s[/\A[A-Za-z0-9_-]+\z/]
      return redirect_to(admin_root_path, alert: 'Enter a record id or a portal record address.') unless id

      redirect_to admin_record_path(id)
    end

    def show
      @predictions = Harvester.predictions(@id)
      @corrections = Harvester.corrections(@id).index_by { |c| c['field'] }
      @text = Harvester.text_status(@id)
      @running = Harvester.running?
    end

    # POST /admin/records/:id/corrections  field, values (one per line; empty clears the field), note
    def correct
      field = params[:field].to_s
      return redirect_to(admin_record_path(@id), alert: 'That field cannot be corrected here.') unless
        Harvester::CORRECTABLE.include?(field) || field == '_scope'

      values = params[:values].to_s.split(/\r?\n/).map(&:strip).reject(&:empty?).uniq
      values = values.first(1) if %w[degree_level degree year title _scope].include?(field)
      if field == 'field_of_study' && values.any? { |v| !v.match?(%r{\A(domains|fields|subfields)/\d+\z}) }
        return redirect_to(admin_record_path(@id), alert: 'Field of study: use OpenAlex ids such as subfields/2739.')
      end
      if field == 'degree_level' && values.any? && !Harvester::LEVELS.include?(values.first)
        return redirect_to(admin_record_path(@id), alert: 'Unknown degree level.')
      end

      ok, out = Harvester.correct(@id, field, values, by: current_admin.email_address, note: params[:note].to_s.strip)
      return redirect_to(admin_record_path(@id), alert: "Correction not saved: #{out.lines.last}") unless ok

      audit('record_corrected', "record:#{@id}", "#{field} = #{values.empty? ? '(cleared)' : values.join(' || ')}" \
                                                 "#{params[:note].present? ? " (#{params[:note].strip})" : ''}")
      redirect_to admin_record_path(@id), notice: "#{field.humanize} corrected. It shows on the portal once the source is " \
                                                  'processed again (tonight, or use Apply now).'
    end

    # DELETE /admin/records/:id/corrections/:field
    def uncorrect
      ok, out = Harvester.uncorrect(@id, params[:field].to_s)
      return redirect_to(admin_record_path(@id), alert: "Not removed: #{out.lines.last}") unless ok

      audit('correction_removed', "record:#{@id}", params[:field].to_s)
      redirect_to admin_record_path(@id), notice: "Correction to #{params[:field].to_s.humanize.downcase} removed."
    end

    # POST /admin/records/:id/apply  process and index the record's source again
    def apply
      if Harvester.start_reprocess(@record['source'])
        audit('reprocess_started', @record['source'], "after corrections to #{@id}")
        redirect_to admin_record_path(@id), notice: 'Processing started; the portal updates in a few minutes.'
      else
        redirect_to admin_record_path(@id), alert: 'A harvest or text extraction is running; corrections apply when the next run processes this source.'
      end
    end

    private

    def load_record
      @id = params[:id].to_s
      @record = Harvester.record(@id) or redirect_to(admin_root_path, alert: "No record #{@id} in the staging store.")
    end
  end
end
