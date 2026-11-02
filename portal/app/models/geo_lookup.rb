# frozen_string_literal: true

require 'maxmind/db'

# Offline IP-to-place lookup for the usage counts (SRS FR-61): DB-IP "IP to City Lite" (CC BY 4.0,
# https://db-ip.com), refreshed monthly on the server (deploy/ops/geoip-update.sh). Nothing is sent to any outside
# service and the address is not kept. Country is reliable; city is approximate (mobile networks in Zambia often
# appear at their Lusaka gateways).
module GeoLookup
  PATH = ENV.fetch('NETD_GEOIP', '/opt/netd/geoip/city.mmdb')
  MUTEX = Mutex.new

  module_function

  # {code:, country:, city:} or nil (no database, private address, or unknown).
  def place(ip)
    db = reader
    return nil unless db && ip.present?

    addr = IPAddr.new(ip)
    return nil if addr.private? || addr.loopback? || addr.link_local?

    rec = db.get(ip)
    return nil unless rec

    { code: rec.dig('country', 'iso_code').to_s, country: rec.dig('country', 'names', 'en').to_s,
      city: rec.dig('city', 'names', 'en').to_s }
  rescue StandardError => e
    Rails.logger.warn("geo lookup failed: #{e.class}: #{e.message}")
    nil
  end

  # Reopened when the file changes (monthly refresh), checked at most once an hour.
  def reader
    MUTEX.synchronize do
      if @checked.nil? || Time.now - @checked > 3600
        @checked = Time.now
        mtime = File.exist?(PATH) ? File.mtime(PATH) : nil
        if mtime != @mtime
          @db&.close
          @db = mtime ? MaxMind::DB.new(PATH, mode: MaxMind::DB::MODE_FILE) : nil
          @mtime = mtime
        end
      end
      @db
    end
  end
end
