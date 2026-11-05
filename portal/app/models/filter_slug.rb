# frozen_string_literal: true

# Readable addresses for the full list of one filter, the list behind a filter's "more" link (FR-71):
# /theses/filters/field-of-study instead of Blacklight's /catalog/facet/fos_field_ssim, which answers 301.
# Field names that are not listed here are used unchanged.
module FilterSlug
  SLUGS = {
    'institution_ssim' => 'institution', 'full_text_ssim' => 'full-text', 'cited' => 'citations',
    'degree_level_ssim' => 'degree-level', 'fos_domain_ssim' => 'research-domain',
    'fos_field_ssim' => 'field-of-study', 'fos_subfield_ssim' => 'subfield', 'faculty_ssim' => 'faculty',
    'department_ssim' => 'department', 'discipline_ssim' => 'programme', 'degree_ssim' => 'degree',
    'supervisor_ssim' => 'supervisor', 'subject_ssim' => 'keywords', 'year_ssim' => 'year', 'author_ssim' => 'author'
  }.freeze
  FIELDS = SLUGS.invert.freeze

  def self.slug(field) = SLUGS.fetch(field.to_s, field.to_s)
  def self.field(slug) = FIELDS.fetch(slug.to_s, slug.to_s)
end
