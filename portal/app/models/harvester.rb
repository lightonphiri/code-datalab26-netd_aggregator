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

  class << self
    def db_path = ENV.fetch('NETD_DB', File.join(HOME, 'netd.sqlite3'))

    # sources.yml (in git) plus sources.local.yml (added from the admin panel), as hashes with string keys.
    def sources
      [File.join(HOME, 'sources.yml'), LOCAL_SOURCES].flat_map do |f|
        File.exist?(f) ? Array(YAML.safe_load_file(f)&.dig('sources')).map { |s| s.merge('local' => f == LOCAL_SOURCES) } : []
      end
    end

    def source(id) = sources.find { |s| s['id'] == id }
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
