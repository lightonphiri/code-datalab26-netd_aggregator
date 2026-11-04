# frozen_string_literal: true

# Record addresses /theses/<short id> (SRS FR-68). The short id drops the DSpace default handle prefix 123456789 that
# every harvested DSpace record id carries (unza-123456789-9150 -> unza-9150); record ids in Solr, the store, usage
# counts, OAI-PMH identifiers and the API stay as they are. Ids without the default prefix (other handle prefixes,
# CSV-loaded sources) are used unchanged. Checked on November 4, 2026: no short id clashes with another record id.
module ThesisId
  DEFAULT_PREFIX = '123456789'
  LONG = /-#{DEFAULT_PREFIX}-(?=\d+\z)/
  SHORT = /\A(.+)-(\d+)\z/

  module_function

  # Record id (or document) -> the id used in addresses.
  def short(id)
    id = id.id if id.respond_to?(:id) && !id.is_a?(String)
    id.to_s.sub(LONG, '-')
  end

  # Address id -> record ids to try, most likely first: unza-9150 may stand for unza-123456789-9150, or be the
  # record id itself (a CSV-loaded source whose identifiers are numbers).
  def candidates(param)
    p = param.to_s
    m = p.match(SHORT)
    m && short(p) == p ? ["#{m[1]}-#{DEFAULT_PREFIX}-#{m[2]}", p] : [p]
  end

  # Address id -> the record id that exists in Solr (nil if none does). One Solr request.
  def resolve(param, connection = Blacklight.default_index.connection)
    ids = candidates(param)
    return ids.first if ids.size == 1

    q = "id:(#{ids.map { |i| RSolr.solr_escape(i) }.join(' OR ')})"
    found = (connection.get('select', params: { q: q, fl: 'id', rows: ids.size, facet: false, spellcheck: false,
                                                wt: 'json' }).dig('response', 'docs') || []).map { |d| d['id'] }
    ids.find { |i| found.include?(i) }
  end
end
