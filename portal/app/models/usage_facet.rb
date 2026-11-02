# frozen_string_literal: true

# Popular searches without storing what anyone typed (SRS FR-61): daily counts of the facet values chosen on a first
# results page. A value is counted only when the search found records, so it is a value present in the index (a
# faculty, degree, subject, year …), never free text.
class UsageFacet < ApplicationRecord
  def self.bump(field, value)
    upsert({ day: Time.now.utc.to_date, field: field.to_s.first(60), value: value.to_s.first(200), hits: 1 },
           unique_by: :index_usage_facets_unique, on_duplicate: Arel.sql('hits = usage_facets.hits + 1'),
           record_timestamps: false)
  rescue StandardError => e
    Rails.logger.warn("usage facet not recorded: #{e.class}: #{e.message}")
  end

  def self.since(days) = where(day: (Time.now.utc.to_date - (days - 1))..)
end
