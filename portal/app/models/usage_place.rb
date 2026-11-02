# frozen_string_literal: true

# Where use comes from (SRS FR-61): daily counts per event, country and approximate city. The reader's IP address is
# looked up in memory (GeoLookup) and discarded; only the place names are counted.
class UsagePlace < ApplicationRecord
  EVENTS = %w[home search browse record_view pdf_download].freeze

  def self.bump(event, place)
    return unless EVENTS.include?(event) && place

    upsert({ day: Time.now.utc.to_date, event: event, country_code: place[:code].to_s.first(2),
             country: place[:country].to_s.first(80), city: place[:city].to_s.first(80), hits: 1 },
           unique_by: :index_usage_places_unique, on_duplicate: Arel.sql('hits = usage_places.hits + 1'),
           record_timestamps: false)
  rescue StandardError => e
    Rails.logger.warn("usage place not recorded: #{e.class}: #{e.message}")
  end

  def self.since(days) = where(day: (Time.now.utc.to_date - (days - 1))..)
end
