# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/stats (FR-45): counts by institution, degree level and year, and field completeness per institution.
    class StatsController < BaseController
      COMPLETENESS = { 'supervisor' => 'supervisor_tsim:*', 'subject' => 'subject_tsim:*',
                       'field_of_study' => 'fos_domain_ssim:*', 'faculty' => 'faculty_tsim:*',
                       'department' => 'department_tsim:*', 'degree' => 'degree_ssim:*', 'degree_level' => 'degree_level_ssim:*',
                       'abstract' => 'abstract_tesim:*', 'full_text' => 'full_text_ssim:"PDF available"' }.freeze

      def index
        render json: { 'data' => cache('stats') { build }, 'meta' => { 'cached_for_seconds' => 600 } }
      end

      private

      def build
        by_source, total = facet('source_ssi')
        levels, = facet('degree_level_ssim')
        years, = facet('year_isi')
        filled = COMPLETENESS.transform_values { |q| facet('source_ssi', fq: q).first }
        sources = Harvester.sources.to_h { |s| [s['id'], s] }
        {
          'total_records' => total,
          'institutions_with_records' => by_source.size,
          'institutions_listed' => InstitutionRegistry.all.size,
          'by_institution' => by_source.sort_by { |_, n| -n }.map do |id, n|
            { 'id' => id, 'name' => sources.dig(id, 'name') || id, 'records' => n,
              'completeness' => COMPLETENESS.keys.to_h { |f| [f, (100.0 * (filled[f][id] || 0) / n).round(1)] } }
          end,
          'by_degree_level' => { 'masters' => levels['Masters'] || 0, 'doctoral' => levels['Doctoral'] || 0,
                                 'postgraduate_diploma' => levels['Postgraduate Diploma'] || 0, 'unknown' => total - levels.values.sum },
          'by_year' => years.sort_by { |y, _| -y.to_i }.map { |y, n| { 'year' => y.to_i, 'records' => n } },
          'completeness' => COMPLETENESS.keys.to_h { |f| [f, total.zero? ? 0 : (100.0 * filled[f].values.sum / total).round(1)] },
          'generated_at' => Time.now.utc.iso8601
        }
      end
    end
  end
end
