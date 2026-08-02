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
#   RESCORE=0     vypne přeměření engagementu (viz níže); default zapnuto
#   RESCORE_LIMIT max. počet přeměřených postů (0 = všechny; default 0)
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
require "zlib"
require "fileutils"
require_relative "../lib/config" # načte config.env do ENV (Surfer credentials apod.)
require_relative "../lib/mastodon_api"

DRY_RUN     = ARGV.include?("--dry-run")
# Přeměření engagementu před sestavením žebříčků. collect_posts ukládá boosty a
# oblíbení v okamžiku sběru, tedy 15 minut až 24 hodin po publikaci (podle toho,
# v kolik post vyšel) — porovnávat taková čísla mezi sebou znamená řadit podle
# různě dlouhého expozičního okna, ne podle úspěchu postu. Tady si čísla stáhneme
# znovu, všechna ve stejný okamžik. Zároveň se tím odhalí smazané posty (404/410),
# které do žebříčků nepatří.
RESCORE       = ENV["RESCORE"] != "0"
RESCORE_LIMIT = (ENV["RESCORE_LIMIT"] || "0").to_i
# Archiv. posts.json drží 6 × 50 postů a přepisuje se každý týden; JSONL se po
# konsolidaci mazal. Ze 3 000+ postů týdne tak trvale nezbylo nic — a Sloník je
# přitom jediný zdroj tvrdých dat o CZ/SK scéně. Držíme proto dvojí stopu:
#   • syrový týden zagzipovaný v data/archive/ (~2 MB z 12 MB), kdyby bylo potřeba
#     se k datům vrátit s jinou otázkou,
#   • souhrn týdne v data/weekly_stats.json — pár kB, ale roste z něj časová řada,
#     kterou jinak nikde nevezmeme.
ARCHIVE       = ENV["ARCHIVE"] != "0"
ARCHIVE_DIR   = ENV["ARCHIVE_DIR"] || File.join(Paths::DATA_DIR, "archive")
STATS_PATH    = ENV["WEEKLY_STATS_PATH"] || File.join(Paths::DATA_DIR, "weekly_stats.json")
STATS_PUBLIC  = ENV["WEEKLY_STATS_PUBLIC"] || File.join(Paths::WEB_DIR, "weekly.json")
TOP_HASHTAGS  = (ENV["TOP_HASHTAGS"] || "50").to_i
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
# Přeměření engagementu (viz RESCORE výše)
# ---------------------------------------------------------------------------

# Stáhne aktuální boosty/oblíbení pro každý post a přepíše je v `posts` na místě.
# Vrací pole postů, které mají do žebříčků jít (bez smazaných). Posty, které se
# nepodaří ověřit (výpadek instance), si ponechají hodnoty ze sběru — horší než
# čerstvé číslo, ale lepší než je z týdne vyhodit.
def rescore!(posts)
  api = MastodonAPI.new(logger: method(:log))
  targets = RESCORE_LIMIT.positive? ? posts.first(RESCORE_LIMIT) : posts
  log("Přeměřuji engagement u #{targets.size} postů (#{posts.size} celkem)…")

  updated = gone = failed = 0
  targets.each_with_index do |p, i|
    host = p["account_instance"].to_s
    sid  = p["id"].to_s
    next if host.empty? || sid.empty?

    code, st, = api.get(host, "/api/v1/statuses/#{URI.encode_www_form_component(sid)}")
    if code == 200 && st.is_a?(Hash)
      p["reblogs_count"]    = st["reblogs_count"] || 0
      p["favourites_count"] = st["favourites_count"] || 0
      p["engagement"]       = p["reblogs_count"] + p["favourites_count"]
      updated += 1
    elsif [404, 410].include?(code)
      p["_gone"] = true    # smazaný / skrytý post → do žebříčků nepatří
      gone += 1
    else
      failed += 1
    end
    log("  … #{i + 1}/#{targets.size} (obnoveno #{updated}, smazaných #{gone}, chyb #{failed})") if ((i + 1) % 250).zero?
  end

  log("Přeměřeno: #{updated} | smazaných vyřazeno: #{gone} | neověřeno (ponechána čísla ze sběru): #{failed}")
  posts.reject { |p| p["_gone"] }
end

# ---------------------------------------------------------------------------
# Žebříčky
# ---------------------------------------------------------------------------

def eng(p)      = p["engagement"] || ((p["reblogs_count"] || 0) + (p["favourites_count"] || 0))
def reblogs(p)  = p["reblogs_count"] || 0
def favs(p)     = p["favourites_count"] || 0

# Vrací `max` nejvyšších podle bloku, sestupně. `max_by(n)` je O(n log max),
# kdežto sort_by.reverse.first(max) seřadí celý týden (tisíce postů) jen proto,
# aby se vzalo padesát — a děje se to šestkrát za běh.
def top_by(posts, max, &block)
  posts.max_by(max, &block)
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
  scored.max_by(max) { |p| p["riser_score"] }
end

def risers_ratio(scored, max)
  scored.select { |p| eng(p) >= RISER_RATIO_MIN_ENG }
        .max_by(max) { |p| p["riser_ratio"] }
end

# ---------------------------------------------------------------------------
# Archiv týdne (viz ARCHIVE výše)
# ---------------------------------------------------------------------------

# Souhrn týdne — to, co z týdne zbyde napořád. Držet celé posty by bylo zbytečné
# (od toho je gzip archiv), tohle je řada, ze které jde číst vývoj scény.
def weekly_stats(posts)
  by_account = posts.group_by { |p| "#{p['account_username']}@#{p['account_instance']}" }
  tags = Hash.new(0)
  posts.each { |p| Array(p["hashtags"]).each { |t| tags[t.to_s.downcase] += 1 } }
  engagements = posts.map { |p| eng(p) }.sort

  {
    "week" => WEEK_LABEL,
    "generated_at" => Time.now.utc.iso8601,
    "total_posts" => posts.size,
    "accounts" => by_account.size,
    "posts_with_media" => posts.count { |p| p["has_media"] },
    "total_reblogs" => posts.sum { |p| reblogs(p) },
    "total_favourites" => posts.sum { |p| favs(p) },
    "total_engagement" => engagements.sum,
    "median_engagement" => (engagements.empty? ? 0 : engagements[engagements.size / 2]),
    "max_engagement" => (engagements.last || 0),
    "posts_without_engagement" => engagements.count(&:zero?),
    "by_instance" => posts.group_by { |p| p["account_instance"] }.transform_values(&:size)
                          .sort_by { |_, n| -n }.to_h,
    "by_family" => posts.group_by { |p| p["account_family"] || "?" }.transform_values(&:size)
                        .sort_by { |_, n| -n }.to_h,
    "by_language" => posts.group_by { |p| p["language"] || "?" }.transform_values(&:size)
                          .sort_by { |_, n| -n }.to_h,
    "top_hashtags" => tags.sort_by { |_, n| -n }.first(TOP_HASHTAGS).to_h,
  }
end

# Přidá souhrn do řady. Týden se klíčuje, takže opakovaná konsolidace téhož
# týdne záznam nahradí místo aby ho zdvojila.
def append_stats(stats)
  series = (JSON.parse(File.read(STATS_PATH, encoding: "UTF-8")) rescue [])
  series = [] unless series.is_a?(Array)
  series.reject! { |w| w["week"] == stats["week"] }
  series << stats
  series.sort_by! { |w| w["week"].to_s }

  FileUtils.mkdir_p(File.dirname(STATS_PATH))
  File.write("#{STATS_PATH}.tmp", JSON.pretty_generate(series))
  File.rename("#{STATS_PATH}.tmp", STATS_PATH)

  FileUtils.mkdir_p(File.dirname(STATS_PUBLIC))
  File.write("#{STATS_PUBLIC}.tmp", JSON.generate({ "weeks" => series.size, "series" => series }))
  File.rename("#{STATS_PUBLIC}.tmp", STATS_PUBLIC)
  log("📈 Řada týdnů: #{series.size} (#{series.first['week']} … #{series.last['week']}) → #{STATS_PATH}")
  series.size
end

# Zagzipuje syrový JSONL do archivu. Vrací cestu k archivu, nebo nil.
def archive_jsonl(path)
  FileUtils.mkdir_p(ARCHIVE_DIR)
  dest = File.join(ARCHIVE_DIR, "#{File.basename(path)}.gz")
  Zlib::GzipWriter.open("#{dest}.tmp") do |gz|
    gz.mtime = File.mtime(path)
    gz.orig_name = File.basename(path)
    File.open(path, "rb") { |f| IO.copy_stream(f, gz) }
  end
  File.rename("#{dest}.tmp", dest)
  log("🗜  Archiv: #{dest} (#{(File.size(path) / 1_048_576.0).round(1)} → #{(File.size(dest) / 1_048_576.0).round(1)} MB)")
  dest
rescue StandardError => e
  log("⚠️  Archivace selhala (#{e.class}: #{e.message}) — JSONL ponechán")
  nil
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

  # Blocklist se uplatní i tady: účet mohl být vyřazen až v průběhu týdne, kdy už
  # měl posty v JSONL. Bez toho by se ještě jednou objevil v žebříčcích.
  blocked = CatalogConfig.read_handle_set("blocklist.txt", env_key: "BLOCKLIST_FILE")
  if blocked.any?
    before = posts.size
    posts = posts.reject { |p| blocked.include?("#{p['account_username']}@#{p['account_instance']}".downcase) }
    dropped = before - posts.size
    log("🚫 Blocklist: vyřazeno #{dropped} postů") if dropped.positive?
    abort("❌ Po vyřazení blocklistu nezbyly žádné posty") if posts.empty?
  end

  accounts = posts.map { |p| "#{p['account_username']}@#{p['account_instance']}" }.uniq
  log("Načteno postů: #{posts.size} | unikátních účtů: #{accounts.size}")

  posts = rescore!(posts) if RESCORE
  abort("❌ Po přeměření nezbyly žádné posty") if posts.empty?

  scored = score_risers(posts)
  result = {
    "week" => WEEK_LABEL,
    "generated_at" => Time.now.utc.iso8601,
    "total_posts" => posts.size,
    "top_by_engagement" => top_by(posts, SECTION_MAX) { |p| eng(p) },
    "top_by_reblogs"    => top_by(posts, SECTION_MAX) { |p| reblogs(p) },
    "top_by_favourites" => top_by(posts, SECTION_MAX) { |p| favs(p) },
    "top_by_date"       => top_by(posts, SECTION_MAX) { |p| p["created_at"].to_s },
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
    log("⚠️  DRY-RUN — archiv, upload i cleanup přeskočeny.")
    return
  end

  # Archiv PŘED uploadem i mazáním: souhrn i zagzipovaný týden musí existovat
  # dřív, než se smaže zdroj, ze kterého vznikly.
  archived = nil
  if ARCHIVE
    append_stats(weekly_stats(posts))
    archived = archive_jsonl(INPUT_PATH)
  end

  uploaded = upload_surfer(OUTPUT_PATH)
  upload_surfer(STATS_PUBLIC) if ARCHIVE && File.exist?(STATS_PUBLIC)

  # Cleanup JSONL jen pokud upload prošel (nebo nebyl konfigurován Surfer a KEEP_JSONL
  # není) A ZÁROVEŇ se povedl archiv — jinak by se syrový týden ztratil nadobro.
  surfer_configured = !ENV["SURFER_URL"].to_s.empty? && !ENV["SURFER_TOKEN"].to_s.empty?
  if ENV["KEEP_JSONL"] == "1"
    log("ℹ️  KEEP_JSONL=1 → JSONL ponechán: #{INPUT_PATH}")
  elsif ARCHIVE && archived.nil?
    log("⚠️  Archivace se nepovedla → JSONL ponechán: #{INPUT_PATH}")
  elsif uploaded || !surfer_configured
    File.delete(INPUT_PATH)
    log("🧹 Smazán JSONL (archiv: #{archived || 'vypnut'})")
  else
    log("⚠️  Upload selhal → JSONL ponechán pro příští pokus: #{INPUT_PATH}")
  end
end

main if __FILE__ == $PROGRAM_NAME
