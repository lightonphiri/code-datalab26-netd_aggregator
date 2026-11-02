# Usage analytics (SRS FR-61, extended November 2, 2026): where use comes from (country, approximate city) and which
# facet values readers choose. Counts per day only: no IP address, user agent, cookie or query text is stored.
class CreateUsagePlacesAndFacets < ActiveRecord::Migration[8.0]
  def change
    create_table :usage_places do |t|
      t.date :day, null: false
      t.string :event, null: false
      t.string :country_code, null: false, default: ''
      t.string :country, null: false, default: ''
      t.string :city, null: false, default: ''
      t.integer :hits, null: false, default: 0
    end
    add_index :usage_places, %i[day event country_code city], unique: true, name: 'index_usage_places_unique'

    create_table :usage_facets do |t|
      t.date :day, null: false
      t.string :field, null: false
      t.string :value, null: false
      t.integer :hits, null: false, default: 0
    end
    add_index :usage_facets, %i[day field value], unique: true, name: 'index_usage_facets_unique'
  end
end
