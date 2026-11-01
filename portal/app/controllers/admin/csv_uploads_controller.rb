# frozen_string_literal: true

module Admin
  # Upload an institution's CSV file (FR-39, FR-40): check it with `netd.cli csv-check`, then put it in place and load it.
  # An HEA institution without a source can be added as a CSV source in the same step.
  class CsvUploadsController < BaseController
    MAX_BYTES = 50.megabytes
    TMP = Rails.root.join('tmp', 'csv_uploads')
    TOKEN = /\A[a-f0-9]{32}\z/

    def new
      @csv_sources = Harvester.csv_sources
      taken = Harvester.sources.map { |s| s['name'] }
      @new_institutions = InstitutionRegistry.names - taken
    end

    def create
      file = params[:file]
      return back_with('Choose a CSV file to upload.') unless file.respond_to?(:path)
      return back_with('The file must have a .csv extension.') unless file.original_filename.to_s.downcase.end_with?('.csv')
      return back_with('The file is larger than 50 MB.') if file.size > MAX_BYTES

      @target = target_from_params or return
      FileUtils.mkdir_p(TMP)
      Dir.glob(TMP.join('*.csv')).each { |f| File.delete(f) if File.mtime(f) < 1.day.ago }
      @token = SecureRandom.hex(16)
      FileUtils.cp(file.path, TMP.join("#{@token}.csv"))
      @filename = file.original_filename
      @ok, @output = Harvester.csv_check(TMP.join("#{@token}.csv").to_s)
      m = @output.match(/(\d+) rows, (\d+) valid, (\d+) with problems/)
      @rows, @valid, @bad = m ? m.captures.map(&:to_i) : [0, 0, 0]
      audit('csv_checked', @target[:id], "#{@filename}: #{@output.lines.last.to_s.strip}")
      render :check
    end

    def load_file
      token = params[:token].to_s
      path = TMP.join("#{token}.csv")
      return back_with('That upload has expired; upload the file again.') unless token.match?(TOKEN) && File.exist?(path)

      target = target_from_params or return
      Harvester.add_csv_source(id: target[:id], name: target[:name], short_name: target[:short_name]) if target[:new]
      installed = Harvester.install_csv(target[:id], path.to_s)
      File.delete(path)
      audit(target[:new] ? 'csv_source_added_and_loaded' : 'csv_loaded', target[:id],
            "#{params[:filename]} -> #{installed}")
      if Harvester.start_run(target[:id])
        audit('harvest_started', target[:id])
        redirect_to admin_source_path(target[:id]), notice: "File installed; loading #{target[:name]} now."
      else
        redirect_to admin_source_path(target[:id]),
                    notice: 'File installed. Another harvest is running; press "Run now" when it has finished, ' \
                            'or the nightly harvest will load it.'
      end
    rescue ArgumentError => e
      back_with(e.message)
    end

    private

    def back_with(msg)
      redirect_to new_admin_csv_upload_path, alert: msg
      nil
    end

    # Existing CSV source (source_id) or a new HEA institution (institution + short_name).
    def target_from_params
      if params[:source_id].present?
        src = Harvester.csv_sources.find { |s| s['id'] == params[:source_id] }
        return back_with('Choose a CSV source.') unless src

        { id: src['id'], name: src['name'], short_name: src['short_name'], new: false }
      else
        name = params[:institution].to_s
        short = params[:short_name].to_s.strip.upcase
        return back_with('Choose an institution.') unless InstitutionRegistry.names.include?(name)
        return back_with('Give a short name of 2 to 16 letters or digits (e.g. CBU).') unless short.match?(/\A[A-Z0-9]{2,16}\z/)

        id = short.downcase
        id = "h#{id}" unless id.match?(/\A[a-z]/)
        return back_with("The source id #{id} is already in use; choose another short name.") if Harvester.source(id)

        { id: id, name: name, short_name: short, new: true }
      end
    end
  end
end
