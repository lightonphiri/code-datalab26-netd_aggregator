# frozen_string_literal: true

# Account roles (SRS FR-36): "admin" (everything) or "viewer" (read-only: reports for HEA, metadata quality, usage).
class AddRoleToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :role, :string, null: false, default: 'admin'
  end
end
