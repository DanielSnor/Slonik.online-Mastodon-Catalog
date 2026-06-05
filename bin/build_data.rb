#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# build_data.rb
#
# Sestaví data.json pro PoC maketu katalogu CZ/SK:
#   1) 50 lidských CZ/SK účtů z ai_results.json (PoC AI kategorizace)
#      → doplní avatar + bio přes Mastodon API (lookup)
#   2) prvních N botů z produkčního katalogu (site/data.json) pro ukázku mixu
#
# Výstup: web/data.json  (formát identický s produkčním katalogem
#         + nové pole `bot` u každého záznamu).
#
# Závislosti: pouze Ruby stdlib. Spuštění:
#   ruby build_data.rb
# ENV:
#   BOTS_COUNT      (default 25)  počet botů z produkce
#   MASTODON_DELAY  (default 0.6) s mezi lookupy
#   SKIP_FETCH=1    nepoužívej síť (avatar/bio fallback) — pro offline build
# =============================================================================

require "json"
require "uri"
require_relative "../lib/config"        # config.env do ENV
require_relative "../lib/mastodon_api"  # lookup
require_relative "../lib/ai"            # map_family + VALID_CATALOG_FAMILIES

AI_JSON   = File.join(Paths::DATA_DIR, "ai_results.json")
# site/ je PoC artefakt přesunutý do archiv/.
PROD_JSON = File.join(Paths::ARCHIV_DIR, "site", "data.json")
OUT_DIR   = Paths::WEB_DIR
OUT_JSON  = File.join(OUT_DIR, "data.json")

BOTS_COUNT     = (ENV["BOTS_COUNT"] || "25").to_i
MASTODON_DELAY = (ENV["MASTODON_DELAY"] || "0.6").to_f
SKIP_FETCH     = ENV["SKIP_FETCH"] == "1"
VALID_FAMILIES = AI::VALID_CATALOG_FAMILIES

def log(msg)
  puts msg
  $stdout.flush
end

API = MastodonAPI.new(logger: method(:log), delay: MASTODON_DELAY)
AICLIENT = AI.new(logger: method(:log))

def mastodon_lookup(instance, username)
  return nil if SKIP_FETCH

  API.lookup(instance, username)
end

def map_family(poc_family)
  AICLIENT.map_family(poc_family)
end

# Sestaví katalogový záznam z jednoho PoC účtu.
def build_person(rec)
  instance = rec["instance"]
  username = rec["username"]
  acct_full = "#{username}@#{instance}"
  profile_url = "https://#{instance}/@#{username}"

  acct = mastodon_lookup(instance, username)
  avatar = acct && acct["avatar"]
  bio = acct && acct["note"]
  bio = "" if bio.nil?

  family = map_family(rec.dig("ai", "family"))
  lang = rec["dominant_language"]
  lang = "cs" if lang.nil? || lang.to_s.empty? # CZ instance → rozumný default

  status = avatar ? "✅" : "⚠️ (bez avataru)"
  log("  #{status} @#{acct_full} → #{family} #{rec.dig('ai', 'tags').inspect}")

  {
    "id" => acct_full,
    # #1: numerické Mastodon id z lookupu → collect_posts.rb přeskočí lookup.
    "mastodon_id" => (acct && acct["id"]),
    "display_name" => rec["display_name"].to_s.empty? ? username : rec["display_name"],
    "type" => "person",
    "family" => family,
    "language" => lang,
    "categories" => Array(rec.dig("ai", "tags")),
    "avatar" => avatar, # nil → app.js zobrazí avatar-fallback
    "bio" => bio,
    "followers" => rec["followers_count"] || 0,
    "posts_week" => 0, # není k dispozici v PoC datech
    "created_at" => (acct && acct["created_at"] ? acct["created_at"][0, 10] : nil),
    "last_status_at" => (acct && acct["last_status_at"] ? acct["last_status_at"][0, 10] : nil),
    "profile_url" => profile_url,
    "source_platforms" => ["mastodon"],
    "source_details" => [
      { "platform" => "mastodon", "handle" => acct_full, "url" => profile_url },
    ],
    "bot" => false,
    "_ai_description" => rec.dig("ai", "description"), # ladící pole, UI ho ignoruje
  }
end

def main
  abort("❌ chybí #{AI_JSON}") unless File.exist?(AI_JSON)
  abort("❌ chybí #{PROD_JSON}") unless File.exist?(PROD_JSON)
  Dir.mkdir(OUT_DIR) unless Dir.exist?(OUT_DIR)

  people_src = JSON.parse(File.read(AI_JSON, encoding: "UTF-8"))
  people_src = people_src.reject { |r| r["error"] } # jen úspěšně kategorizované
  log("Lidských účtů ke zpracování: #{people_src.size}")

  people = people_src.map { |rec| build_person(rec) }

  # Boti z produkce: prvních N záznamů, doplníme bot=true.
  prod = JSON.parse(File.read(PROD_JSON, encoding: "UTF-8"))
  bots = prod.first(BOTS_COUNT).map do |r|
    r2 = r.dup
    r2["bot"] = true
    r2
  end
  log("Botů z produkce: #{bots.size} (z #{prod.size})")

  combined = people + bots
  File.write(OUT_JSON, JSON.pretty_generate(combined))

  # Souhrn
  fam = people.map { |p| p["family"] }.tally
  miss_avatar = people.count { |p| p["avatar"].nil? }
  log("")
  log("Zapsáno #{OUT_JSON}")
  log("  celkem záznamů: #{combined.size} (lidé #{people.size} + boti #{bots.size})")
  log("  rodiny lidí: #{fam.inspect}")
  log("  lidí bez avataru (fallback): #{miss_avatar}")
  bad_fam = people.map { |p| p["family"] }.uniq - VALID_FAMILIES
  log("  ⚠️ neznámé rodiny: #{bad_fam.inspect}") unless bad_fam.empty?
end

main if __FILE__ == $PROGRAM_NAME
