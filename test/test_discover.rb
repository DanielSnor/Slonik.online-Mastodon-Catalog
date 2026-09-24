# frozen_string_literal: true

require_relative "helper"
require "date"

# discover_accounts.rb se dá načíst bez spuštění (main je za `__FILE__` guardem).
load_script("../bin/discover_accounts.rb")

# Brána aktivity. Nález z 24. 9. 2026: sledující velkých účtů jsou z většiny
# čtenáři; bez brány by mlčící účty z .cz/.sk instancí prošly placenou AI
# a nafoukly katalog, který je už ze tří čtvrtin mrtvý.
class TestCandidateActivityGate < Minitest::Test
  TODAY = Date.new(2026, 9, 24)

  def acc(last: nil, statuses: 0)
    { "last_status_at" => last, "statuses_count" => statuses }
  end

  def test_recent_post_passes
    assert recently_active?(acc(last: "2026-09-20T10:00:00.000Z"), today: TODAY, window: 90)
    assert recently_active?(acc(last: "2026-06-26"), today: TODAY, window: 90), "přesně na hranici okna"
  end

  def test_old_post_is_rejected
    refute recently_active?(acc(last: "2026-06-25"), today: TODAY, window: 90), "den za hranicí"
    refute recently_active?(acc(last: "2023-01-01", statuses: 5000), today: TODAY, window: 90),
           "starý účet s tisíci postů je pořád mlčící — rozhoduje datum, ne počet"
  end

  # Mastodon: chybějící last_status_at = nikdy nepublikoval.
  def test_never_posted_is_rejected
    refute recently_active?(acc, today: TODAY, window: 90)
  end

  # Pixelfed last_status_at nevrací vůbec — jeho aktivní účty mají nil i při
  # stovkách postů (ověřeno na jiri.kalina@pixelfed.cz: nil, 257 postů).
  def test_missing_date_with_posts_passes_for_pixelfed
    assert recently_active?(acc(statuses: 257), today: TODAY, window: 90)
  end

  def test_broken_date_is_rejected
    refute recently_active?(acc(last: "nesmysl", statuses: 10), today: TODAY, window: 90)
  end

  def test_zero_window_disables_the_gate
    assert recently_active?(acc(last: "2019-01-01"), today: TODAY, window: 0)
    assert recently_active?(acc, today: TODAY, window: 0)
  end
end

# add_account je jediné místo, kudy do kandidátů vstupují followers i directory
# — brána musí sedět tady, jinak by ji jeden ze zdrojů obešel.
class TestAddAccountGate < Minitest::Test
  def follower(acct, last:, statuses: 10, bot: false)
    { "acct" => acct, "username" => acct.split("@").first, "display_name" => acct,
      "followers_count" => 1, "statuses_count" => statuses, "bot" => bot, "last_status_at" => last }
  end

  def test_active_follower_is_added
    into = {}
    assert add_account(into, follower("aktivni", last: Date.today.to_s), "witter.cz")
    assert_equal ["aktivni@witter.cz"], into.keys
  end

  def test_silent_follower_is_not_added
    into = {}
    before = STATS[:inactive]
    refute add_account(into, follower("mlcici", last: (Date.today - 400).to_s), "witter.cz")
    assert_empty into
    assert_equal before + 1, STATS[:inactive], "vyřazení se počítá do statistiky běhu"
  end

  def test_bot_is_rejected_before_the_gate
    into = {}
    before = STATS[:inactive]
    refute add_account(into, follower("bot", last: Date.today.to_s, bot: true), "witter.cz")
    assert_equal before, STATS[:inactive]
  end
end

# Zdroj 3: účty z lokálních timeline (users.json). Directory vydá jen účty se
# zapnutou viditelností; 181 aktivních lidí bylo 24. 9. 2026 mimo katalog právě
# proto — timeline je vidí při psaní.
class TestTimelineCandidates < Minitest::Test
  TODAY = Date.new(2026, 9, 24)

  def user(a, cat:, last:, fo: 10, np: 3)
    { "a" => a, "n" => a.split("@").first, "i" => a.split("@").last, "fo" => fo, "np" => np,
      "last" => last, "cat" => cat }
  end

  def test_active_non_catalog_account_becomes_candidate
    out = timeline_candidates([user("tichotlapka@cztwitter.cz", cat: false, last: "2026-09-24T08:00:00.000Z")],
                              today: TODAY, window: 90, dead: [])
    assert_equal 1, out.size
    c = out.first
    assert_equal "tichotlapka@cztwitter.cz", c["acct"]
    assert_equal "tichotlapka", c["username"]
    assert_equal "cztwitter.cz", c["instance"]
    assert_equal false, c["bot"]
  end

  def test_catalog_accounts_are_skipped
    out = timeline_candidates([user("prahou@merveilles.town", cat: true, last: "2026-09-24")],
                              today: TODAY, window: 90, dead: [])
    assert_empty out
  end

  def test_stale_and_missing_dates_are_skipped
    out = timeline_candidates([user("stary@f.cz", cat: false, last: "2026-01-01"),
                               user("bezdata@f.cz", cat: false, last: nil)],
                              today: TODAY, window: 90, dead: [])
    assert_empty out
  end

  def test_dead_instances_and_bridges_are_skipped
    out = timeline_candidates([user("duch@mastodon.arch-linux.cz", cat: false, last: "2026-09-24"),
                               user("x.bsky.social@bsky.brid.gy", cat: false, last: "2026-09-24")],
                              today: TODAY, window: 90, dead: ["mastodon.arch-linux.cz"])
    assert_empty out
  end

  def test_leading_at_and_garbage_are_tolerated
    out = timeline_candidates([user("@jmeno@witter.cz", cat: false, last: "2026-09-24"),
                               { "a" => "bezinstance", "cat" => false, "last" => "2026-09-24" },
                               "nesmysl", nil],
                              today: TODAY, window: 90, dead: [])
    assert_equal ["jmeno@witter.cz"], out.map { |c| c["acct"] }
  end
end
