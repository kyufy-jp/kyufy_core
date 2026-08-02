require "test_helper"
require "kyufy_core/data_export"

module KyufyCore
  # data/*.json is a published interface for consumers outside Ruby (data/README.md), generated
  # from Geo's constants and db/seeds/programs/*.yml. Silent drift would hand those consumers a
  # different geography or a different 要綱 excerpt than the engine itself uses — the export is
  # only trustworthy if regenerating it is enforced, not remembered.
  class DataExportTest < ActiveSupport::TestCase
    DataExport.documents.each do |relative_path, expected|
      test "#{relative_path} is up to date" do
        path = File.join(DataExport::ROOT, relative_path)
        assert File.exist?(path), "#{relative_path} is missing — run `bundle exec rake data:export`"
        assert_equal expected, JSON.parse(File.read(path)),
          "#{relative_path} is stale — run `bundle exec rake data:export`"
      end
    end

    # The export exists to be consumed without Ruby, so the invariants a consumer would rely on
    # are asserted here rather than left to the generator's good behavior.
    test "geo codes are strings, so leading zeros survive" do
      geo = DataExport.geo

      assert_equal "01", geo["prefectures"]["北海道"]
      assert_equal "13101", geo["municipalities"]["千代田区"]
      assert_includes geo["designated_cities"], "01100"
      assert(geo["municipalities"].values.all? { |code| code.is_a?(String) && code.length == 5 })
    end

    test "ambiguous bare ward names stay out of the municipality table" do
      municipalities = DataExport.geo["municipalities"]

      # 中央区 and 北区 exist in several cities; a bare key would silently resolve to one of them.
      assert_not municipalities.key?("中央区")
      assert_not municipalities.key?("北区")
      assert municipalities.key?("中央区（東京都）")
      assert municipalities.key?("さいたま市中央区")
    end

    test "every exported requirement carries a verbatim citation and a reachable source" do
      programs = DataExport.programs["programs"]

      assert_equal 5, programs.size
      programs.each do |program|
        assert program["official_url"].start_with?("https://"), "#{program["name"]}: no official_url"
        assert program["requirements"].any?, "#{program["name"]}: no requirements"

        program["requirements"].each do |requirement|
          assert requirement["raw_text"].to_s.strip.present?,
            "#{program["name"]}/#{requirement["kind"]}: raw_text is the citation — it can't be blank"
        end
      end
    end
  end
end
