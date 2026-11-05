# frozen_string_literal: true

# A fixed list of codes whose labels are interface text in portal/config/locales/en.yml (packaging P4e, NFR-15).
# Labels are looked up at each use, so the request's language applies. It answers [], fetch, key?, keys, each,
# each_key, each_value, map and to_h like the frozen hash it replaces, so callers stay unchanged.
#   LocalisedLabels.new('netd.institution_status', %w[harvested ...])           # code => label
#   LocalisedLabels.new('netd.quality_groups', %w[...], fields: %w[label description])  # code => [label, description]
class LocalisedLabels
  include Enumerable

  def initialize(scope, codes, fields: nil)
    @scope = scope
    @codes = codes.map(&:to_s).freeze
    @fields = fields
  end

  def keys = @codes
  def key?(code) = @codes.include?(code.to_s)

  def [](code)
    return nil unless key?(code)

    @fields ? @fields.map { |f| I18n.t("#{@scope}.#{code}.#{f}") } : I18n.t("#{@scope}.#{code}")
  end

  def fetch(code, *default)
    return self[code] if key?(code)
    return yield(code) if block_given?
    return default.first unless default.empty?

    raise KeyError, "key not found: #{code.inspect}"
  end

  def to_h = @codes.to_h { |c| [c, self[c]] }
  def each(&) = to_h.each(&)
  def each_key(&) = @codes.each(&)
  def each_value(&) = to_h.each_value(&)
end
