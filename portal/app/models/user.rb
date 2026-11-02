# frozen_string_literal: true

# Admin panel account (FR-36). Created from the command line only (bin/rails netd:user:add), never by sign-up.
# Role "admin" can use everything; "viewer" (e.g. HEA staff) can only read the reports, metadata quality and usage.
class User < ApplicationRecord
  ROLES = %w[admin viewer].freeze
  has_secure_password
  has_many :sessions, dependent: :destroy
  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :password, length: { minimum: 12 }, allow_nil: true
  validates :role, inclusion: { in: ROLES }

  def admin? = role == 'admin'
  def viewer? = role == 'viewer'
end
