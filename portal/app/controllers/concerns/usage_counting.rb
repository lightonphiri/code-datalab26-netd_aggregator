# frozen_string_literal: true

# Counts page use for the usage analytics (SRS FR-61) without third-party trackers. Requests from crawlers, link
# previews, prefetches, monitors and signed-in administrators are not counted.
module UsageCounting
  extend ActiveSupport::Concern

  BOT = /bot|crawl|spider|slurp|archiver|facebookexternalhit|embedly|preview|curl|wget|python|java\/|go-http|
         httpclient|okhttp|libwww|scrapy|headless|phantom|monitor|uptime|check|scan|feed|validator/xi

  private

  def count_usage(event, record_id: '', institution: '', bots: false)
    return unless bots || human_visit?

    UsageCount.bump(event, record_id: record_id, institution: institution)
  end

  def human_visit?
    ua = request.user_agent.to_s
    return false if ua.blank? || ua.match?(BOT)
    return false if [request.headers['Sec-Purpose'], request.headers['Purpose'], request.headers['X-Moz']].compact
                                                                                                    .any? { |v| v.to_s.include?('prefetch') }

    cookies.signed[AdminAuthentication::COOKIE].blank?
  end
end
