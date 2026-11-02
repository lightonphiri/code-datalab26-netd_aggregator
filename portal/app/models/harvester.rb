# frozen_string_literal: true

require 'open3'
require 'sqlite3'

# The admin panel's view of the Python harvester (FR-37, FR-39, FR-40): its source registry, run log and CSV loader.
# The staging store is opened read-only; anything that changes it runs through `netd.cli` as a background process,
# under the same lock as the nightly harvest so the two never overlap.
class Harvester
  HOME = ENV.fetch('NETD_HARVESTER', Rails.root.join('..', 'harvester').to_s)
  PYTHON = File.join(HOME, '.venv', 'bin', 'python')
  LOCK = File.join(HOME, 'run.lock')
  LOCAL_SOURCES = ENV.fetch('NETD_SOURCES_LOCAL', File.join(HOME, 'sources.local.yml'))
  UPLOADS = ENV.fetch('NETD_UPLOADS', File.join(HOME, 'uploads'))
  LOGS = ENV.fetch('NETD_LOGS', File.expand_path(File.join(HOME, '..', 'logs')))
  ID_PATTERN = /\A[a-z][a-z0-9]{1,15}\z/
  CORRECTABLE = %w[field_of_study degree_level degree discipline supervisor department faculty subject year title author].freeze  # FR-51
  LEVELS = ['Doctoral', 'Masters', 'Postgraduate Diploma', 'Bachelors'].freeze

  class << self
    def db_path = ENV.fetch('NETD_DB', File.join(HOME, 'netd.sqlite3'))

    # sources.yml (in git) plus sources.local.yml (added from the admin panel), as hashes with string keys.
    def sources
      [File.join(HOME, 'sources.yml'), LOCAL_SOURCES].flat_map do |f|
        File.exist?(f) ? Array(YAML.safe_load_file(f)&.dig('sources')).map { |s| s.merge('local' => f == LOCAL_SOURCES) } : []
      end
    end

    def source(id) = sources.find { |s| s['id'] == id }

    # Latest weekly repository check (netd.cli check-repositories, FR-58), or nil.
    def repository_check
      JSON.parse(File.read(File.join(LOGS, 'repository-check.json')))
    rescue Errno::ENOENT, JSON::ParserError
      nil
    end
    def csv_sources = sources.select { |s| s['loader'] == 'csv' }

    def store
      SQLite3::Database.new(db_path, readonly: true, results_as_hash: true)
    end

    # Latest run per source, and per-source counts in the staging store.
    def status
      db = store
      runs = db.execute('SELECT * FROM harvest_runs WHERE id IN (SELECT max(id) FROM harvest_runs GROUP BY source)')
               .to_h { |r| [r['source'], r] }
      counts = db.execute('SELECT source, count(*) n FROM records GROUP BY source').to_h { |r| [r['source'], r['n']] }
      { runs: runs, counts: counts }
    rescue SQLite3::Exception => e
      { runs: {}, counts: {}, error: e.message }
    ensure
      db&.close
    end

    def recent_runs(source, limit = 10)
      db = store
      db.execute('SELECT * FROM harvest_runs WHERE source=? ORDER BY id DESC LIMIT ?', [source, limit])
    rescue SQLite3::Exception
      []
    ensure
      db&.close
    end

    def excluded(source)
      db = store
      db.execute('SELECT * FROM excluded WHERE source=? ORDER BY id', [source])
    rescue SQLite3::Exception
      []
    ensure
      db&.close
    end

    # --- metadata filling (FR-14, FR-49 to FR-52) ---------------------------------------------------------------
    def query(sql, binds = [])
      db = store
      db.execute(sql, binds)
    rescue SQLite3::Exception
      []
    ensure
      db&.close
    end

    # A record as the store holds it (after cleaning, predictions and corrections), or nil.
    def record(id)
      row = query('SELECT data FROM records WHERE id=?', [id]).first
      row ||= query("SELECT json_object('id', id, 'source', source, 'title', json_array(title), " \
                    "'excluded', reason) data FROM excluded WHERE id=?", [id]).first
      row && JSON.parse(row['data'])
    end

    def predictions(id) = query('SELECT * FROM predictions WHERE record_id=? ORDER BY field, confidence DESC', [id])
    def corrections(id) = query('SELECT * FROM corrections WHERE record_id=? ORDER BY field', [id])
    def text_status(id) = query('SELECT status, pages, message, fetched_at FROM pdf_text WHERE record_id=?', [id]).first

    def level_review(status = 'pending')
      query('SELECT l.*, json_extract(r.data, "$.title[0]") title, json_extract(r.data, "$.pdf_url[0]") pdf, ' \
            'json_extract(r.data, "$.institution_short") inst FROM level_review l LEFT JOIN records r ON r.id = l.record_id ' \
            'WHERE l.status=? ORDER BY l.confidence DESC, l.record_id', [status])
    end

    # FR-19: duplicate groups as [{ 'primary' => row, 'copies' => [rows] }]; rows carry id, title, author, year, pdf, method, score.
    def duplicate_groups
      rec = 'json_extract(r.data, "$.title[0]") title, json_extract(r.data, "$.author[0]") author, ' \
            'json_extract(r.data, "$.year[0]") year, json_extract(r.data, "$.pdf_url[0]") pdf, r.source source'
      rows = query("SELECT d.id, d.primary_id, d.method, d.score, #{rec} FROM duplicates d LEFT JOIN records r ON r.id = d.id " \
                   'ORDER BY d.primary_id, d.id')
      mains = query("SELECT r.id, #{rec} FROM records r WHERE r.id IN (SELECT DISTINCT primary_id FROM duplicates)").to_h { |m| [m['id'], m] }
      rows.group_by { |r| r['primary_id'] }.map { |pid, copies| { 'primary' => mains[pid] || { 'id' => pid }, 'copies' => copies } }
    end

    def duplicate_decisions
      query('SELECT c.*, json_extract(r.data, "$.title[0]") title FROM corrections c LEFT JOIN records r ON r.id = c.record_id ' \
            "WHERE c.field='_duplicate' ORDER BY c.created_at DESC")
    end

    def duplicate_count = query('SELECT count(DISTINCT primary_id) n FROM duplicates').first&.fetch('n', 0).to_i

    def corrections_count = query('SELECT count(*) n FROM corrections').first&.fetch('n', 0).to_i
    def review_count = query("SELECT count(*) n FROM level_review WHERE status='pending'").first&.fetch('n', 0).to_i

    # `netd.cli correct RECORD FIELD VALUE... --by EMAIL --note NOTE` -> [ok?, output]
    def correct(id, field, values, by:, note: nil)
      args = [PYTHON, '-m', 'netd.cli', 'correct', id, field, *values, '--by', by]
      args += ['--note', note] if note.present?
      out, status = Open3.capture2e(*args, chdir: HOME)
      [status.success?, out]
    end

    def uncorrect(id, field)
      out, status = Open3.capture2e(PYTHON, '-m', 'netd.cli', 'uncorrect', id, field, chdir: HOME)
      [status.success?, out]
    end

    # Process and index one source again (no harvest), so corrections show at once; false if a run is going.
    def start_reprocess(id)
      return false if running?

      FileUtils.mkdir_p(LOGS)
      pid = Process.spawn('flock', '-n', LOCK, PYTHON, '-m', 'netd.cli', 'reprocess', '--source', id,
                          chdir: HOME, out: [File.join(LOGS, "admin-run-#{id}.log"), 'w'], err: [:child, :out], pgroup: true)
      Process.detach(pid)
      true
    end

    def running?
      File.open(LOCK, File::RDWR | File::CREAT, 0o644) { |f| !f.flock(File::LOCK_EX | File::LOCK_NB) }
    rescue SystemCallError
      false
    end

    # `netd.cli csv-check FILE` -> [ok?, output]
    def csv_check(path)
      out, status = Open3.capture2e(PYTHON, '-m', 'netd.cli', 'csv-check', path, chdir: HOME)
      [status.success?, out]
    end

    # Start `netd.cli run --source ID` in the background; false if a harvest is already running.
    def start_run(id)
      return false if running?

      FileUtils.mkdir_p(LOGS)
      log = File.join(LOGS, "admin-run-#{id}.log")
      pid = Process.spawn('flock', '-n', LOCK, PYTHON, '-m', 'netd.cli', 'run', '--source', id,
                          chdir: HOME, out: [log, 'w'], err: [:child, :out], pgroup: true)
      Process.detach(pid)
      true
    end

    def run_log(id)
      f = File.join(LOGS, "admin-run-#{id}.log")
      File.exist?(f) ? File.read(f).lines.last(40).join : nil
    end

    # Put a checked CSV file in place as the source's current file (the previous one is archived).
    def install_csv(id, tmp_path)
      dir = File.join(UPLOADS, id)
      FileUtils.mkdir_p(File.join(dir, 'archive'))
      current = File.join(dir, 'records.csv')
      FileUtils.mv(current, File.join(dir, 'archive', "records-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.csv")) if File.exist?(current)
      FileUtils.cp(tmp_path, current)
      current
    end

    # Register an HEA institution as a CSV source in sources.local.yml.
    def add_csv_source(id:, name:, short_name:)
      raise ArgumentError, 'Source id: 2-16 lower-case letters or digits, starting with a letter' unless id.match?(ID_PATTERN)
      raise ArgumentError, "Source id #{id} is already in use" if source(id)
      raise ArgumentError, "#{name} already has a source" if sources.any? { |s| s['name'] == name }
      raise ArgumentError, "#{name} is not in the HEA institution list" unless InstitutionRegistry.names.include?(name)

      data = File.exist?(LOCAL_SOURCES) ? (YAML.safe_load_file(LOCAL_SOURCES) || {}) : {}
      data['sources'] = Array(data['sources']) + [{ 'id' => id, 'name' => name, 'short_name' => short_name,
                                                     'loader' => 'csv', 'csv_path' => File.join(UPLOADS, id) }]
      tmp = "#{LOCAL_SOURCES}.tmp"
      File.write(tmp, "# Sources added from the admin panel (CSV institutions). Read together with sources.yml.\n" +
                      data.to_yaml)
      File.rename(tmp, LOCAL_SOURCES)
    end
  end
end
