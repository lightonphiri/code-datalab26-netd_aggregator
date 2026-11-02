# Usage analytics (SRS FR-61): one row per day, event, record and institution, holding a count. No IP address, user
# agent, cookie or query text is stored.
class CreateUsageCounts < ActiveRecord::Migration[8.0]
  def change
    create_table :usage_counts do |t|
      t.date :day, null: false
      t.string :event, null: false
      t.string :record_id, null: false, default: ''
      t.string :institution, null: false, default: ''
      t.integer :hits, null: false, default: 0
    end
    add_index :usage_counts, %i[day event record_id institution], unique: true, name: 'index_usage_counts_unique'
    add_index :usage_counts, %i[event day]
  end
end
