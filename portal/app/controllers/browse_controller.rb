# frozen_string_literal: true

# Browse by institution, faculty or school, and department (FR-25), with counts of theses (each thesis once, FR-19).
# One Solr request with two pivots; cached for 10 minutes.
class BrowseController < ApplicationController
  include Blacklight::Configurable
  copy_blacklight_config_from(CatalogController)
  layout 'blacklight'

  def index
    @tree = Rails.cache.fetch('browse/tree', expires_in: 10.minutes) { tree }
  end

  private

  def tree
    res = Blacklight.default_index.connection.get('select', params: {
      q: '*:*', rows: 0, fq: '-duplicate_of_ssi:[* TO *]', facet: true, 'facet.limit': -1, 'facet.mincount': 1,
      'facet.pivot': ['institution_ssim,faculty_ssim', 'institution_ssim,faculty_department_ssim']
    })
    pivots = res.dig('facet_counts', 'facet_pivot') || {}
    depts = Array(pivots['institution_ssim,faculty_department_ssim']).to_h do |i|
      by_fac = Hash.new { |h, k| h[k] = [] }
      Array(i['pivot']).each do |p|
        fac, dept = p['value'].split('|', 2)
        by_fac[fac] << { 'name' => dept, 'count' => p['count'] } if dept
      end
      [i['value'], by_fac]
    end
    Array(pivots['institution_ssim,faculty_ssim']).map do |i|
      facs = Array(i['pivot']).map do |f|
        { 'name' => f['value'], 'count' => f['count'],
          'departments' => depts.dig(i['value'], f['value']).to_a.sort_by { |d| [-d['count'], d['name']] } }
      end
      { 'name' => i['value'], 'count' => i['count'], 'faculties' => facs.sort_by { |f| f['name'] },
        'without_faculty' => i['count'] - facs.sum { |f| f['count'] } }
    end
  end
end
