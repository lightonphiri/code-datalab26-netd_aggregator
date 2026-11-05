# frozen_string_literal: true

# Aggregate usage counts (SRS FR-61): searches, record views, PDF downloads, API and OAI-PMH requests per day.
# Privacy by design: only the day, the kind of event, the record id and its institution are kept, as a count.
class UsageCount < ApplicationRecord
  # Kinds of use; labels in portal/config/locales/en.yml under netd.usage_events (packaging P4g)
  EVENTS = LocalisedLabels.new('netd.usage_events', %w[home search browse record_view pdf_download api oai])

  # Adds one to today's count (UTC day). Never raises: analytics must not break a page.
  def self.bump(event, record_id: '', institution: '')
    raise ArgumentError, "unknown event #{event}" unless EVENTS.key?(event)

    upsert({ day: Time.now.utc.to_date, event: event, record_id: record_id.to_s.first(100),
             institution: institution.to_s.first(100), hits: 1 },
           unique_by: :index_usage_counts_unique, on_duplicate: Arel.sql('hits = usage_counts.hits + 1'),
           record_timestamps: false)
  rescue StandardError => e
    Rails.logger.warn("usage count not recorded (#{event}): #{e.class}: #{e.message}")
  end

  def self.since(days) = where(day: (Time.now.utc.to_date - (days - 1))..)
end
