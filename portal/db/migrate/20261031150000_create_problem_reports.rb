class CreateProblemReports < ActiveRecord::Migration[8.0]
  def change
    create_table :problem_reports do |t|
      t.string :problem, null: false
      t.text :message, null: false
      t.string :name
      t.string :email, null: false
      t.string :record_url
      t.string :record_title
      t.string :remote_ip
      t.boolean :emailed, default: false, null: false
      t.text :email_error
      t.timestamps
    end
  end
end
