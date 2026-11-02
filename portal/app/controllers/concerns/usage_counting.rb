# frozen_string_literal: true

# Counts page use for the usage analytics (SRS FR-61) without third-party trackers. The reader's place (country,
# approximate city) is looked up offline and only the place is counted, never the address. Requests from crawlers, link
# previews, prefetches, monitors and signed-in administrators are not counted.
module UsageCounting
  extend ActiveSupport::Concern

  BOT = /bot|crawl|spider|slurp|archiver|facebookexternalhit|embedly|preview|curl|wget|python|java\/|go-http|
         httpclient|okhttp|libwww|scrapy|headless|phantom|monitor|uptime|check|scan|feed|validator|
         censys|inspect|zgrab|nmap|masscan|nuclei|httpx|fasthttp|axios|node-fetch|aiohttp|netcraft|expanse/xi
  # Browsers always name their platform after "Mozilla/5.0"; scanners often send "Mozilla/5.0 AppleWebKit/..." (seen
  # November 2, 2026). Tests that should not be counted use a user agent with "check" (docs/OPERATIONS.md).
  NO_PLATFORM = %r{\AMozilla/5\.0 (?!\()}

  private

  def count_usage(event, record_id: '', institution: '', bots: false)
    return unless bots || human_visit?

    UsageCount.bump(event, record_id: record_id, institution: institution)
    UsagePlace.bump(event, GeoLookup.place(request.remote_ip)) if UsagePlace::EVENTS.include?(event)
  end

  def human_visit?
    ua = request.user_agent.to_s
    return false if ua.blank? || ua.match?(BOT) || ua.match?(NO_PLATFORM)
    return false if [request.headers['Sec-Purpose'], request.headers['Purpose'], request.headers['X-Moz']].compact
                                                                                                    .any? { |v| v.to_s.include?('prefetch') }

    cookies.signed[AdminAuthentication::COOKIE].blank?
  end
end
