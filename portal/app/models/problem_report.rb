# frozen_string_literal: true

# A problem reported from a record page (saved even if email delivery fails).
class ProblemReport < ApplicationRecord
  PROBLEMS = [
    'The download link resulted in an error',
    'The full text is missing or is the wrong file',
    'The metadata is wrong or incomplete',
    'This is a duplicate record',
    'Other'
  ].freeze

  validates :problem, inclusion: { in: PROBLEMS }
  validates :message, presence: true, length: { maximum: 5000 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, length: { maximum: 200 }
end
