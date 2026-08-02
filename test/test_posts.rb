# frozen_string_literal: true

require_relative "helper"
require "date"

load_script("../bin/consolidate_posts.rb")

class TestPostRankings < Minitest::Test
  def post(acct, eng, created: "2026-06-01T10:00:00Z", tags: [], lang: "cs")
    user, inst = acct.split("@", 2)
    { "id" => "#{acct}-#{eng}-#{created}", "account_username" => user, "account_instance" => inst,
      "reblogs_count" => eng, "favourites_count" => 0, "engagement" => eng,
      "created_at" => created, "hashtags" => tags, "language" => lang, "has_media" => false }
  end

  def test_top_by_returns_highest_first
    posts = [post("a@x.cz", 1), post("b@x.cz", 9), post("c@x.cz", 5)]
    assert_equal [9, 5, 1], top_by(posts, 3) { |p| eng(p) }.map { |p| eng(p) }
  end

  def test_top_by_caps_the_section
    posts = (1..100).map { |i| post("a@x.cz", i) }
    assert_equal 50, top_by(posts, 50) { |p| eng(p) }.size
  end

  def test_top_by_matches_a_full_sort
    srand(42)
    posts = (1..500).map { |i| post("a@x.cz", rand(100), created: "2026-06-0#{(i % 9) + 1}T10:00:00Z") }
    expected = posts.sort_by { |p| eng(p) }.reverse.first(50).map { |p| eng(p) }
    assert_equal expected, top_by(posts, 50) { |p| eng(p) }.map { |p| eng(p) }
  end

  # Skokani porovnávají post s průměrem VLASTNÍHO účtu, takže účet s příliš málo
  # posty se vylučuje — jinak by průměr byl náhoda.
  def test_risers_skip_accounts_with_too_few_posts
    posts = [post("a@x.cz", 10), post("a@x.cz", 20)]
    assert_empty score_risers(posts)
  end

  def test_riser_score_and_ratio
    posts = [post("a@x.cz", 0), post("a@x.cz", 0), post("a@x.cz", 9)]
    top = score_risers(posts).max_by { |p| p["riser_score"] }
    assert_in_delta 3.0, top["account_avg_engagement"], 0.01
    assert_in_delta 6.0, top["riser_score"], 0.01
    assert_in_delta 3.0, top["riser_ratio"], 0.01
  end

  def test_ratio_ranking_ignores_tiny_numbers
    # Účet s průměrem 1/3 a jedním postem s engagementem 1 má poměr 3.0, ale
    # jeden boost není „skokan týdne" — proto práh RISER_RATIO_MIN_ENG.
    quiet = [post("a@x.cz", 0), post("a@x.cz", 0), post("a@x.cz", 1)]
    assert_empty risers_ratio(score_risers(quiet), 50)

    loud = [post("b@x.cz", 0), post("b@x.cz", 0), post("b@x.cz", 30)]
    assert_equal 1, risers_ratio(score_risers(loud), 50).size
  end

  def test_weekly_stats_summarise_the_week
    posts = [post("a@x.cz", 10, tags: %w[brno test]), post("a@x.cz", 0, tags: ["brno"]),
             post("b@y.sk", 4, lang: "sk")]
    s = weekly_stats(posts)
    assert_equal 3, s["total_posts"]
    assert_equal 2, s["accounts"]
    assert_equal 14, s["total_engagement"]
    assert_equal 10, s["max_engagement"]
    assert_equal 1, s["posts_without_engagement"]
    assert_equal({ "x.cz" => 2, "y.sk" => 1 }, s["by_instance"])
    assert_equal({ "cs" => 2, "sk" => 1 }, s["by_language"])
    assert_equal 2, s["top_hashtags"]["brno"]
  end
end

# Jméno týdenního JSONL musí u collectu a konsolidace vyjít stejně, jinak
# konsolidace hledá soubor, který nikdo nevyrobil. Kritický je přelom roku:
# `year` a `cwyear` se tam rozcházejí.
class TestIsoWeek < Minitest::Test
  def jsonl_for(date)
    y, w = week_of(date)
    format("posts_%04d_W%02d.jsonl", y, w)
  end

  def test_year_boundary_uses_the_iso_week_year
    # 2025-12-29 je pondělí W01 roku 2026 — kalendářní rok je 2025, ISO rok 2026.
    assert_equal "posts_2026_W01.jsonl", jsonl_for(Date.new(2025, 12, 29))
    assert_equal "posts_2026_W01.jsonl", jsonl_for(Date.new(2026, 1, 1))
    # 2027-01-01 je pátek posledního týdne roku 2026.
    assert_equal "posts_2026_W53.jsonl", jsonl_for(Date.new(2027, 1, 1))
  end

  def test_every_day_of_a_week_lands_in_the_same_file
    monday = Date.new(2026, 6, 1)
    names = (0..6).map { |i| jsonl_for(monday + i) }
    assert_equal 1, names.uniq.size, names.uniq.inspect
  end

  # Konsolidace běží v pondělí a bere týden, který skončil včera (v neděli).
  def test_monday_consolidation_targets_the_week_that_just_ended
    (0..60).each do |i|
      monday = Date.new(2025, 12, 1) + (i * 7)
      assert_equal 1, monday.cwday, "kontrolní datum musí být pondělí"
      assert_equal week_of(monday - 1), week_of(monday - 7),
                   "pondělí #{monday}: konsolidovaný týden musí být ten, co skončil v neděli"
    end
  end
end
