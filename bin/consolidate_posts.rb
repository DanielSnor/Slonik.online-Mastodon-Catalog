#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# consolidate_posts.rb
#
# Týdenní konsolidace postů (cron Po 03:00). Načte JSONL předchozího týdne,
# spočítá žebříčky a skokany, vygeneruje posts.json, uploadne na Surfer a
# smaže JSONL.
#
# Závislosti: pouze Ruby stdlib (net/http, json, uri, date, time).
# Spuštění:
#   ruby consolidate_posts.rb                 # předchozí týden, upload+cleanup
#   ruby consolidate_posts.rb --dry-run       # negeneruje upload, nemaže JSONL
#   WEEK_OVERRIDE=2026-W22 ruby consolidate_posts.rb   # konkrétní týden
#   INPUT_JSONL=/tmp/x.jsonl ruby consolidate_posts.rb # explicitní vstupní soubor
#
# ENV:
#   OUTPUT_DIR    adresář pro JSONL + posts.json (default .)
#   WEEK_OVERRIDE YYYY-Www — který týden konsolidovat (default minulý týden)
#   INPUT_JSONL   explicitní cesta k JSONL (přebije WEEK_OVERRIDE)
#   SURFER_URL    base URL Surferu (např. https://katalog-test.zpravobot.news)
#   SURFER_TOKEN  Surfer access_token (Files API)
#   SURFER_REMOTE_DIR  cílová podsložka na Surferu (default "" = root; např. "slonik-test")
#   KEEP_JSONL=1  nemazat JSONL po konsolidaci
# =============================================================================

require "net/http"
require "json"
require "uri"
require "date"
require "time"
require_relative "../lib/config" # načte config.env do ENV (Surfer credentials apod.)

DRY_RUN     = ARGV.include?("--dry-run")
OUTPUT_DIR  = ENV["OUTPUT_DIR"] || Paths::DATA_DIR  # kde leží týdenní JSONL
SECTION_MAX = 50           # max postů na sekci (frontend bere Top 10 / Top 50)
RISER_MIN_POSTS = 3        # min. počet postů účtu pro výpočet skokanů
RISER_RATIO_MIN_ENG = 5    # min. engagement pro poměrovou metriku skokanů
USER_AGENT  = "mastokatalog-consolidate/1.0 (+https://katalog-test.zpravobot.news)"

def log(msg)
  puts "#{Time.now.utc.strftime('%H:%M:%S')} #{msg}"
  $stdout.flush
end

# ---------------------------------------------------------------------------
# Který týden
# ---------------------------------------------------------------------------

# Vrací [cwyear, cweek, "YYYY-Www"] pro daný týden.
def resolve_week
  if ENV["WEEK_OVERRIDE"] && ENV["WEEK_OVERRIDE"] =~ /\A(\d{4})-W(\d{2})\z/
    [Regexp.last_match(1).to_i, Regexp.last_match(2).to_i]
  else
    # Minulý týden (consolidate běží v pondělí pro týden, který skončil v neděli).
    d = Date.today - 7
    [d.cwyear, d.cweek]
  end
end

CWYEAR, CWEEK = resolve_week
WEEK_LABEL    = format("%04d-W%02d", CWYEAR, CWEEK)
JSONL_NAME    = format("posts_%04d_W%02d.jsonl", CWYEAR, CWEEK)
INPUT_PATH    = ENV["INPUT_JSONL"] || File.join(OUTPUT_DIR, JSONL_NAME)
OUTPUT_PATH   = ENV["POSTS_OUTPUT"] || File.join(Paths::WEB_DIR, "posts.json")

# ---------------------------------------------------------------------------
# Načtení + parsování JSONL
# ---------------------------------------------------------------------------

def load_posts(path)
  posts = []
  File.foreach(path, encoding: "UTF-8") do |line|
    line = line.strip
    next if line.empty?

    begin
      posts << JSON.parse(line)
    rescue JSON::ParserError => e
      log("  ⚠️  přeskakuji nevalidní řádek: #{e.message}")
    end
  end
  posts
end

# ---------------------------------------------------------------------------
# Žebříčky
# ---------------------------------------------------------------------------

def eng(p)      = p["engagement"] || ((p["reblogs_count"] || 0) + (p["favourites_count"] || 0))
def reblogs(p)  = p["reblogs_count"] || 0
def favs(p)     = p["favourites_count"] || 0

def top_by(posts, max, &block)
  posts.sort_by(&block).reverse.first(max)
end

# Skokani týdne — posty, které překonaly vlastní průměr účtu, dvěma metrikami:
#   • riser_score = engagement − průměr účtu        (absolutní nadvýkon / „dosahem")
#   • riser_ratio = engagement ÷ průměr účtu         (poměr k průměru / „poměrem")
# Účty s < RISER_MIN_POSTS posty se vyloučí (nespolehlivý průměr). Poměrová
# metrika navíc vyžaduje engagement ≥ RISER_RATIO_MIN_ENG (ať nešumí drobné účty).
def score_risers(posts)
  by_account = posts.group_by { |p| "#{p['account_username']}@#{p['account_instance']}" }
  scored = []
  by_account.each_value do |acc_posts|
    next if acc_posts.size < RISER_MIN_POSTS

    avg = acc_posts.sum { |p| eng(p) }.to_f / acc_posts.size
    acc_posts.each do |p|
      e = eng(p)
      ratio = avg.positive? ? (e / avg) : 0.0
      scored << p.merge(
        "account_avg_engagement" => avg.round(2),
        "riser_score" => (e - avg).round(2),
        "riser_ratio" => ratio.round(2)
      )
    end
  end
  scored
end

def risers_absolute(scored, max)
  scored.sort_by { |p| p["riser_score"] }.reverse.first(max)
end

def risers_ratio(scored, max)
  scored.select { |p| eng(p) >= RISER_RATIO_MIN_ENG }
        .sort_by { |p| p["riser_ratio"] }.reverse.first(max)
end

# ---------------------------------------------------------------------------
# Upload — sdílená logika v lib/config.rb (Surfer.upload), aby ji sdílel
# i update_catalog.rb. Vrací true při úspěchu.
# ---------------------------------------------------------------------------

def upload_surfer(path)
  Surfer.upload(path, logger: method(:log)) == :ok
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main
  log("Konsolidace týdne #{WEEK_LABEL} | vstup: #{INPUT_PATH} | dry-run: #{DRY_RUN}")
  unless File.exist?(INPUT_PATH)
    abort("❌ JSONL nenalezen: #{INPUT_PATH} (za daný týden nejsou žádné posty?)")
  end

  posts = load_posts(INPUT_PATH)
  if posts.empty?
    abort("❌ JSONL je prázdný: #{INPUT_PATH}")
  end

  accounts = posts.map { |p| "#{p['account_username']}@#{p['account_instance']}" }.uniq
  log("Načteno postů: #{posts.size} | unikátních účtů: #{accounts.size}")

  scored = score_risers(posts)
  result = {
    "week" => WEEK_LABEL,
    "generated_at" => Time.now.utc.iso8601,
    "total_posts" => posts.size,
    "top_by_engagement" => top_by(posts, SECTION_MAX) { |p| eng(p) },
    "top_by_reblogs"    => top_by(posts, SECTION_MAX) { |p| reblogs(p) },
    "top_by_favourites" => top_by(posts, SECTION_MAX) { |p| favs(p) },
    "top_by_date"       => posts.sort_by { |p| p["created_at"].to_s }.reverse.first(SECTION_MAX),
    "risers_absolute"   => risers_absolute(scored, SECTION_MAX),
    "risers_ratio"      => risers_ratio(scored, SECTION_MAX),
  }

  File.write(OUTPUT_PATH, JSON.pretty_generate(result))
  log("✅ Zapsáno #{OUTPUT_PATH} (#{File.size(OUTPUT_PATH)} B)")

  # Souhrn / top post týdne
  top = result["top_by_engagement"].first
  if top
    log("🏆 Top post týdne: @#{top['account_username']}@#{top['account_instance']} " \
        "(engagement #{eng(top)}) — #{top['content_plain'].to_s[0, 60].gsub("\n", ' ')}")
  end
  log("📊 Sekce: engagement=#{result['top_by_engagement'].size}, reblogs=#{result['top_by_reblogs'].size}, " \
      "favourites=#{result['top_by_favourites'].size}, date=#{result['top_by_date'].size}, " \
      "risers_abs=#{result['risers_absolute'].size}, risers_ratio=#{result['risers_ratio'].size}")

  if DRY_RUN
    log("⚠️  DRY-RUN — upload a cleanup přeskočeny.")
    return
  end

  uploaded = upload_surfer(OUTPUT_PATH)

  # Cleanup JSONL jen pokud upload prošel (nebo nebyl konfigurován Surfer a KEEP_JSONL není).
  surfer_configured = !ENV["SURFER_URL"].to_s.empty? && !ENV["SURFER_TOKEN"].to_s.empty?
  if ENV["KEEP_JSONL"] == "1"
    log("ℹ️  KEEP_JSONL=1 → JSONL ponechán: #{INPUT_PATH}")
  elsif uploaded || !surfer_configured
    File.delete(INPUT_PATH)
    log("🧹 Smazán JSONL: #{INPUT_PATH}")
  else
    log("⚠️  Upload selhal → JSONL ponechán pro příští pokus: #{INPUT_PATH}")
  end
end

main if __FILE__ == $PROGRAM_NAME
