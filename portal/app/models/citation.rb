# frozen_string_literal: true

require 'citeproc'
require 'csl'

# "How to cite" (SRS FR-65): a record as one CSL item, rendered in the same citation styles OJS offers, from the
# official CSL style files in config/csl (citation-style-language/styles, CC BY-SA 3.0) with British English terms.
# Also RIS (EndNote, Zotero, Mendeley) and BibTeX. The link cited is the item on the institution's own repository
# (the version of record); the portal's record page is cited only when the repository link is unusable.
class Citation
  DIR = Rails.root.join('config/csl')
  # key => [label, file], in OJS's order
  STYLES = {
    'acm' => ['ACM', 'acm-sig-proceedings'],
    'acs' => ['ACS', 'american-chemical-society'],
    'apa' => ['APA', 'apa'],
    'abnt' => ['ABNT', 'associacao-brasileira-de-normas-tecnicas'],
    'chicago' => ['Chicago', 'chicago-author-date'],
    'harvard' => ['Harvard', 'harvard-cite-them-right'],
    'ieee' => ['IEEE', 'ieee'],
    'mla' => ['MLA', 'modern-language-association'],
    'turabian' => ['Turabian', 'turabian'],
    'vancouver' => ['Vancouver', 'vancouver']
  }.freeze
  DEFAULT = 'apa'
  GENRE = { 'Doctoral' => 'Doctoral thesis', 'Masters' => "Master's thesis",
            'Postgraduate Diploma' => 'Postgraduate diploma dissertation' }.freeze

  def self.locale = (@locale ||= CSL::Locale.load(DIR.join('locales-en-GB.xml').to_s))
  def self.style(key) = (@styles ||= {})[key] ||= CSL::Style.load(DIR.join("#{STYLES.fetch(key).last}.csl").to_s)

  # Usable repository link: http(s), a real host (not localhost) and not an unregistered handle.net address.
  def self.repository_link(url)
    u = URI.parse(url.to_s)
    return nil unless %w[http https].include?(u.scheme) && u.host.to_s.include?('.')
    return nil if u.host == 'hdl.handle.net' && u.path.start_with?('/123456789/')
    return nil if u.path.match?(%r{/edit(/|\z)})

    u.to_s
  rescue URI::InvalidURIError
    nil
  end

  def initialize(doc, portal_url)
    @doc = doc
    @portal_url = portal_url
  end

  def v(field) = Array(@doc[field]).first.to_s.strip

  def url = self.class.repository_link(v('url_ssm')) || @portal_url

  def authors
    Array(@doc['author_ssim']).map do |a|
      if a.include?(',')
        family, given = a.split(',', 2).map(&:strip)
      else
        parts = a.split
        family = parts.pop
        given = parts.join(' ')
      end
      { 'family' => family, 'given' => given.presence }.compact
    end
  end

  # Markup in harvested values must not reach the page: citeproc-ruby escapes "&" but passes "<" and ">" through,
  # so they are escaped before rendering (the view also sanitises the result).
  def self.html_text(s) = s.to_s.gsub('<', '&lt;').gsub('>', '&gt;')

  def item(html: false)
    t = html ? self.class.method(:html_text) : ->(s) { s }
    {
      'id' => @doc.id, 'type' => 'thesis', 'title' => t.(v('title_tsim').presence || v('title_ssm')),
      'author' => authors.map { |a| a.transform_values { |x| t.(x) } }, 'issued' => (y = v('year_ssim')).present? ? { 'date-parts' => [[y.to_i]] } : nil,
      'genre' => GENRE[v('degree_level_ssim')], 'publisher' => t.(v('institution_ssim')).presence, 'URL' => url
    }.compact
  end

  # HTML-safe bibliography entry (citeproc-ruby escapes the values; markup is the style's own).
  def render(key)
    key = DEFAULT unless STYLES.key?(key)
    cp = CiteProc::Processor.new(style: self.class.style(key), locale: self.class.locale, format: 'html')
    cp << item(html: true)
    Array(cp.render(:bibliography, id: @doc.id)).first.to_s
  end

  def ris
    lines = [%w[TY THES]]
    authors.each { |a| lines << ['AU', [a['family'], a['given']].compact.join(', ')] }
    lines << ['TI', item['title']] << ['PY', v('year_ssim')] << ['PB', v('institution_ssim')]
    lines << ['M3', item['genre']] << ['UR', url] << ['DB', 'Zambia National ETD Portal'] << ['ER', '']
    lines.reject { |k, val| val.blank? && k != 'ER' }.map { |k, val| "#{k}  - #{val}".rstrip }.join("\r\n") + "\r\n"
  end

  def bibtex
    entry = v('degree_level_ssim') == 'Doctoral' ? 'phdthesis' : 'mastersthesis'
    key = (authors.first&.dig('family').to_s + v('year_ssim')).gsub(/[^A-Za-z0-9]/, '').presence || @doc.id
    esc = ->(s) { s.to_s.gsub(/([{}&%$#_])/) { "\\#{Regexp.last_match(1)}" } }
    fields = { 'author' => authors.map { |a| [a['family'], a['given']].compact.join(', ') }.join(' and '),
               'title' => item['title'], 'school' => v('institution_ssim'), 'year' => v('year_ssim'),
               'type' => item['genre'], 'url' => url }.reject { |_, val| val.blank? }
    "@#{entry}{#{key},\n" + fields.map { |k, val| "  #{k} = {#{k == 'url' ? val : esc.(val)}}" }.join(",\n") + "\n}\n"
  end
end
