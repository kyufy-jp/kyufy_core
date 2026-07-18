require "test_helper"

module KyufyCore
  class GeoTest < ActiveSupport::TestCase
    # --- normalization ---

    test "normalizes a 特別区 to its own JIS code with no parent city" do
      r = Geo.normalize("新宿区")
      assert_equal "13", r.prefecture_code
      assert_equal "13104", r.municipality_code
      assert_nil Geo.parent_city_of("13104"), "特別区 must not normalize to a parent city"
    end

    test "normalizes a designated-city ward to the ward code, with parent city derivable" do
      r = Geo.normalize("さいたま市中央区")
      assert_equal "11105", r.municipality_code
      assert_equal "11100", Geo.parent_city_of("11105")
    end

    test "normalizes a prefecture to prefecture granularity (no municipality)" do
      r = Geo.normalize("東京都")
      assert_equal "13", r.prefecture_code
      assert_nil r.municipality_code
    end

    test "normalizes a prefecture-prefixed municipality" do
      r = Geo.normalize("埼玉県さいたま市中央区")
      assert_equal "11105", r.municipality_code
    end

    test "returns nil for unresolvable / ambiguous residence" do
      assert_nil Geo.normalize("ZZZ不明")
      assert_nil Geo.normalize("中央区"), "bare ambiguous ward name must fail rather than mis-match"
      assert_nil Geo.normalize("")
      assert_nil Geo.normalize(nil)
    end

    test "a designated city code has no parent" do
      assert_nil Geo.parent_city_of("11100")
    end

    test "parent lookup picks the correct city when a prefecture has several designated cities" do
      # 川崎市 (14130) wards floor to 14100 (横浜市) under a naive rule; must resolve to 川崎.
      assert_equal "14130", Geo.parent_city_of("14131")
      assert_equal "14100", Geo.parent_city_of("14101")
    end

    # --- applies: match / ancestor / none ---

    def applies(residence, jurisdiction:, prefecture_code: nil, municipality_code: nil)
      Geo.applies(Geo.normalize(residence), jurisdiction: jurisdiction,
                  prefecture_code: prefecture_code, municipality_code: municipality_code)
    end

    test "national programs always match" do
      assert_equal :match, applies("新宿区", jurisdiction: "national")
    end

    test "prefecture program matches any resident of that prefecture" do
      assert_equal :match, applies("新宿区", jurisdiction: "prefecture", prefecture_code: "13")
      assert_equal :match, applies("東京都", jurisdiction: "prefecture", prefecture_code: "13")
      assert_equal :none,  applies("さいたま市中央区", jurisdiction: "prefecture", prefecture_code: "13")
    end

    test "municipality program: exact ward match" do
      assert_equal :match, applies("新宿区", jurisdiction: "municipality",
                                   prefecture_code: "13", municipality_code: "13104")
    end

    test "municipality program: ward resident matches parent-city program" do
      assert_equal :match, applies("さいたま市中央区", jurisdiction: "municipality",
                                   prefecture_code: "11", municipality_code: "11100")
    end

    test "municipality program: non-matching ward does not apply" do
      assert_equal :none, applies("新宿区", jurisdiction: "municipality",
                                  prefecture_code: "13", municipality_code: "13102")
    end

    test "ancestor: prefecture-level residence vs a finer municipality program passes through" do
      assert_equal :ancestor, applies("東京都", jurisdiction: "municipality",
                                      prefecture_code: "13", municipality_code: "13104")
    end

    test "ancestor: designated-city residence vs one of its ward programs passes through" do
      assert_equal :ancestor, applies("さいたま市", jurisdiction: "municipality",
                                      prefecture_code: "11", municipality_code: "11105")
    end
  end
end
