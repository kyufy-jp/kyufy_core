module KyufyCore
  # Geographic applicability (§4). Residence free text -> JIS X 0401/0402 codes, plus the
  # hierarchy semantics that decide whether a program applies to a resident:
  #   national ⊃ prefecture ⊃ municipality all apply simultaneously.
  #
  # Codes are kept as STRINGS to preserve leading zeros (e.g. 札幌市 = "01100").
  module Geo
    # A normalized residence. municipality_code is nil when the residence is only
    # resolved to prefecture granularity (e.g. "東京都").
    Residence = Struct.new(:prefecture_code, :municipality_code, :raw, keyword_init: true)

    # All 47 prefectures: name -> JIS X 0401 (2-digit) code.
    PREFECTURES = {
      "北海道" => "01", "青森県" => "02", "岩手県" => "03", "宮城県" => "04", "秋田県" => "05",
      "山形県" => "06", "福島県" => "07", "茨城県" => "08", "栃木県" => "09", "群馬県" => "10",
      "埼玉県" => "11", "千葉県" => "12", "東京都" => "13", "神奈川県" => "14", "新潟県" => "15",
      "富山県" => "16", "石川県" => "17", "福井県" => "18", "山梨県" => "19", "長野県" => "20",
      "岐阜県" => "21", "静岡県" => "22", "愛知県" => "23", "三重県" => "24", "滋賀県" => "25",
      "京都府" => "26", "大阪府" => "27", "兵庫県" => "28", "奈良県" => "29", "和歌山県" => "30",
      "鳥取県" => "31", "島根県" => "32", "岡山県" => "33", "広島県" => "34", "山口県" => "35",
      "徳島県" => "36", "香川県" => "37", "愛媛県" => "38", "高知県" => "39", "福岡県" => "40",
      "佐賀県" => "41", "長崎県" => "42", "熊本県" => "43", "大分県" => "44", "宮崎県" => "45",
      "鹿児島県" => "46", "沖縄県" => "47"
    }.freeze

    # The 20 政令指定都市 (designated cities), JIS X 0402 codes ending in "00" (plus the
    # second-city offsets 30/40/50). This list is the ONLY data the ward->parent-city logic
    # needs: 東京23区 have no "13100" city here, so they are never treated as wards (see below).
    DESIGNATED_CITY_CODES = %w[
      01100 04100 11100 12100 14100 14130 14150 15100 22100 22130
      23100 26100 27100 27140 28100 33100 34100 40100 40130 43100
    ].freeze

    # Municipality full name -> JIS X 0402 (5-digit) code. Only names needed by the seed +
    # tests are enumerated (a full national table would be generated at ingestion time). Bare
    # ambiguous ward names ("中央区", "北区") are deliberately NOT keyed here: they resolve to
    # normalization failure -> 要確認, never a wrong match.
    #
    # Hosts add their own via `config.extra_municipalities` (see Configuration and the
    # `municipalities` method below); this constant stays the packaged data.
    MUNICIPALITIES = {
      # 東京都特別区 (13101–13123) — each a full municipality, NO parent city.
      "千代田区" => "13101", "中央区（東京都）" => "13102", "港区（東京都）" => "13103",
      "新宿区" => "13104", "文京区" => "13105", "台東区" => "13106", "墨田区" => "13107",
      "江東区" => "13108", "品川区" => "13109", "目黒区" => "13110", "大田区" => "13111",
      "世田谷区" => "13112", "渋谷区" => "13113", "中野区" => "13114", "杉並区" => "13115",
      "豊島区" => "13116", "荒川区" => "13118", "板橋区" => "13119", "練馬区" => "13120",
      "足立区" => "13121", "葛飾区" => "13122", "江戸川区" => "13123",
      # さいたま市 (designated city 11100) + its 10 wards.
      "さいたま市" => "11100",
      "さいたま市西区" => "11101", "さいたま市北区" => "11102", "さいたま市大宮区" => "11103",
      "さいたま市見沼区" => "11104", "さいたま市中央区" => "11105", "さいたま市桜区" => "11106",
      "さいたま市浦和区" => "11107", "さいたま市南区" => "11108", "さいたま市緑区" => "11109",
      "さいたま市岩槻区" => "11110"
    }.freeze

    module_function

    # The table lookups actually use: the packaged constant plus config.extra_municipalities.
    # MUNICIPALITIES stays the canonical packaged data (data/geo.json exports the constant, not
    # this), so a host's additions never leak into the export or into another host's view.
    def municipalities
      extras = configured_extra_municipalities
      return MUNICIPALITIES if extras.empty?

      # Keyed on object identity: Configuration freezes and replaces the hash on assignment, so
      # a new object always means new content, and reassignment takes effect immediately.
      cached = @municipalities_cache
      return cached.last if cached && cached.first.equal?(extras)

      merged = MUNICIPALITIES.merge(extras).freeze
      @municipalities_cache = [ extras, merged ]
      merged
    end

    # data_export.rb requires this file on its own (no Rails, no configuration), so tolerate a
    # half-loaded library rather than making a pure-data module hard-depend on global config.
    def configured_extra_municipalities
      return {} unless KyufyCore.respond_to?(:config)

      KyufyCore.config.extra_municipalities
    end

    # Free text -> Residence, or nil on failure (caller applies carve-out (a): don't exclude).
    def normalize(text)
      return nil if text.nil?

      s = text.to_s.strip
      return nil if s.empty?

      table = municipalities

      if (code = table[s])
        return Residence.new(prefecture_code: code[0, 2], municipality_code: code, raw: s)
      end

      if (pref = PREFECTURES[s])
        return Residence.new(prefecture_code: pref, municipality_code: nil, raw: s)
      end

      # Prefecture-prefixed municipality, e.g. "埼玉県さいたま市中央区" / "東京都新宿区".
      PREFECTURES.each_key do |pref_name|
        next unless s.start_with?(pref_name)

        rest = s[pref_name.length..]
        if (code = table[rest])
          return Residence.new(prefecture_code: code[0, 2], municipality_code: code, raw: s)
        end
      end

      nil
    end

    # Parent designated-city code for a ward code, or nil. Data-light: the largest designated
    # city code in the same prefecture that sits just below the ward within its 100-block.
    # 東京23区 return nil (no designated city 131xx), so they are never normalized to a parent.
    def parent_city_of(municipality_code)
      return nil if municipality_code.nil?

      n = municipality_code.to_i
      pref = municipality_code[0, 2]
      best = nil
      DESIGNATED_CITY_CODES.each do |c|
        ci = c.to_i
        next unless c[0, 2] == pref
        next unless ci < n
        next unless n - ci < 100
        best = c if best.nil? || ci > best.to_i
      end
      best
    end

    # Does a program apply to this (already-normalized, non-nil) residence?
    # Returns :match, :ancestor (carve-out (b): residence coarser than program scope
    # -> pass through to 要確認), or :none (correct omission).
    def applies(residence, jurisdiction:, prefecture_code:, municipality_code:)
      return :match if jurisdiction == "national"

      case jurisdiction
      when "prefecture"
        residence.prefecture_code == prefecture_code ? :match : :none
      when "municipality"
        m = municipality_code
        r = residence.municipality_code
        if r
          if r == m
            :match
          elsif parent_city_of(r) == m
            :match          # ward resident matches parent-city program
          elsif parent_city_of(m) == r
            :ancestor       # residence is the parent city of the program's ward
          else
            :none
          end
        elsif m && residence.prefecture_code == m[0, 2]
          :ancestor         # residence resolved only to prefecture; program is finer-scoped
        else
          :none
        end
      else
        :none
      end
    end
  end
end
