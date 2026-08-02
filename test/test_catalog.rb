# frozen_string_literal: true

require_relative "helper"
require "date"

# update_catalog.rb se dá načíst bez spuštění (main je za `__FILE__` guardem).
load_script("../bin/update_catalog.rb")

class TestCatalogHelpers < Minitest::Test
  def rec(id, last_status_at: nil, verified: nil, family: nil)
    r = { "id" => id, "last_status_at" => last_status_at }
    r["last_verified_at"] = verified if verified
    r["family"] = family if family
    r
  end

  def days_ago(n)
    (Date.today - n).to_s
  end

  # Chybějící last_status_at znamená „účet nikdy nic nepublikoval" — ne chybu
  # sběru. Kdyby se to četlo obráceně, tvářil by se jako čerstvě aktivní.
  def test_never_posted_is_not_active
    assert_nil days_since_post(rec("a@x.cz"))
    refute active?(rec("a@x.cz"))
    assert_equal :silent, refresh_tier(rec("a@x.cz"))
  end

  def test_activity_window
    assert active?(rec("a@x.cz", last_status_at: days_ago(1)))
    assert active?(rec("a@x.cz", last_status_at: days_ago(ACTIVE_DAYS)))
    refute active?(rec("a@x.cz", last_status_at: days_ago(ACTIVE_DAYS + 1)))
  end

  def test_broken_date_does_not_blow_up
    assert_nil days_since_post(rec("a@x.cz", last_status_at: "nesmysl"))
    refute active?(rec("a@x.cz", last_status_at: "nesmysl"))
  end

  def test_refresh_tiers
    assert_equal :active,  refresh_tier(rec("a@x.cz", last_status_at: days_ago(10)))
    assert_equal :dormant, refresh_tier(rec("a@x.cz", last_status_at: days_ago(200)))
    assert_equal :silent,  refresh_tier(rec("a@x.cz", last_status_at: days_ago(400)))
  end

  def test_active_accounts_refresh_every_run
    r = rec("a@x.cz", last_status_at: days_ago(1), verified: Date.today.to_s)
    assert due_for_refresh?(r), "aktivní účet se obnovuje vždy, i když byl ověřen dnes"
  end

  def test_dormant_accounts_wait_for_their_interval
    fresh = rec("a@x.cz", last_status_at: days_ago(200), verified: days_ago(1))
    due   = rec("a@x.cz", last_status_at: days_ago(200), verified: days_ago(REFRESH_DORMANT))
    refute due_for_refresh?(fresh)
    assert due_for_refresh?(due)
  end

  def test_records_without_a_verification_stamp_are_always_due
    assert due_for_refresh?(rec("a@x.cz", last_status_at: days_ago(400))),
           "záznam z doby před značkou se musí obnovit, jinak by čekal navždy"
  end

  # Dedup drží živý záznam, ne ten mrtvý — jinak by migrovaný účet nebo duplicita
  # lišící se velikostí písmen mohly přepsat aktuální data starými.
  def test_dedup_is_case_insensitive_and_keeps_the_liveliest
    out = dedup_by_id([
                        rec("Franta@x.cz", last_status_at: "2026-01-01"),
                        rec("franta@x.cz", last_status_at: "2026-07-01"),
                        rec("jiny@x.cz",   last_status_at: "2026-05-01")
                      ])
    assert_equal 2, out.size
    franta = out.find { |r| r["id"].downcase == "franta@x.cz" }
    assert_equal "2026-07-01", franta["last_status_at"]
  end

  def test_dedup_prefers_the_earlier_record_on_a_tie
    out = dedup_by_id([
                        rec("a@x.cz", last_status_at: "2026-07-01", family: "prvni"),
                        rec("a@x.cz", last_status_at: "2026-07-01", family: "druhy")
                      ])
    assert_equal 1, out.size
    assert_equal "prvni", out.first["family"], "při shodě zůstává kurátorovaný (dřívější) záznam"
  end

  def test_dedup_keeps_a_dated_record_over_one_that_never_posted
    out = dedup_by_id([rec("a@x.cz"), rec("a@x.cz", last_status_at: "2026-07-01")])
    assert_equal 1, out.size
    assert_equal "2026-07-01", out.first["last_status_at"]
  end

  def test_dedup_preserves_order
    out = dedup_by_id([rec("b@x.cz"), rec("a@x.cz"), rec("c@x.cz")])
    assert_equal %w[b@x.cz a@x.cz c@x.cz], out.map { |r| r["id"] }
  end

  # Cíl migrace se čte z pole `moved`; když v něm chybí doména, dopočítá se z URL.
  def test_moved_target
    assert_equal "novy@jiny.cz", moved_target("moved" => { "acct" => "novy@jiny.cz" })
    assert_equal "novy@jiny.cz", moved_target("moved" => { "acct" => "novy", "url" => "https://jiny.cz/@novy" })
    assert_equal "novy@jiny.cz", moved_target("moved" => { "acct" => "Novy@Jiny.cz" })
    assert_nil moved_target({})
    assert_nil moved_target("moved" => { "acct" => "bezdomeny" })
  end

  # Publikovaný payload nesmí obsahovat interní pole — hlavně _ai_description,
  # tedy strojově psané charakteristiky lidí, které web nikde nezobrazuje.
  def test_public_keys_exclude_internal_fields
    %w[_ai_description mastodon_id source_details last_verified_at unverified_since
       verify_failures].each do |k|
      refute_includes PUBLIC_KEYS, k
    end
  end

  def test_public_keys_cover_what_the_frontend_renders
    %w[id display_name type family language categories avatar bio followers
       posts_week created_at last_status_at profile_url source_platforms bot
       followers_delta activity_delta].each do |k|
      assert_includes PUBLIC_KEYS, k
    end
  end
end
