# Admin panel (SRS FR-36 to FR-41): accounts, sign-in sessions, audit log, and resolution of problem reports.
class CreateAdminTables < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :name, null: false
      t.string :password_digest, null: false
      t.boolean :active, default: true, null: false
      t.boolean :must_change_password, default: true, null: false
      t.datetime :last_sign_in_at
      t.timestamps
    end
    add_index :users, :email_address, unique: true

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end

    create_table :admin_events do |t|
      t.references :user, foreign_key: true
      t.string :action, null: false
      t.string :subject
      t.text :detail
      t.string :ip_address
      t.datetime :created_at, null: false
    end
    add_index :admin_events, :created_at

    change_table :problem_reports do |t|
      t.string :status, default: 'open', null: false
      t.datetime :resolved_at
      t.references :resolved_by
      t.text :admin_note
    end
  end
end
