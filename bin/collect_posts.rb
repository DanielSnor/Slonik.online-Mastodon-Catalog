#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# collect_posts.rb
#
# Denní sběr postů ze všech účtů katalogu (cron Po–Ne 23:30).
# Pro každý účet stáhne posty za aktuální den (UTC) a appenduje je do
# týdenního JSONL souboru `posts_YYYY_Www.jsonl` (ISO week).
#
# Závislosti: pouze Ruby stdlib (net/http, json, uri, date, time).
# Spuštění:
#   ruby collect_posts.rb              # ostrý běh (dnešní den UTC)
#   ruby collect_posts.rb --yesterday  # předchozí (uzavřený) den — pro běh po půlnoci
#   DATE_OVERRIDE=2026-06-01 ruby collect_posts.rb   # simulace konkrétního dne
#   ruby collect_posts.rb --dry-run    # nezapisuje, jen loguje
#
# ENV:
#   MASTODON_TOKEN   read-only bearer token (volitelný)
#   MASTODON_DELAY   sekundy mezi requesty (default 1.0)
#   DATA_JSON_PATH   cesta ke katalogu účtů (default data.json)
#   OUTPUT_DIR       adresář pro JSONL (default .)
#   DATE_OVERRIDE    YYYY-MM-DD — simulace dne (jinak dnešek UTC)
# =============================================================================

require "net/http"
require "json"
require "uri"
require "date"
require "time"
require_relative "../lib/config"        # config.env do ENV
require_relative "../lib/mastodon_api"  # HTTP + rate limit + strip_html

DRY_RUN = ARGV.include?("--dry-run")

MASTODON_TOKEN = ENV["MASTODON_TOKEN"]
MASTODON_DELAY = (ENV["MASTODON_DELAY"] || "1.0").to_f
DATA_JSON_PATH = ENV["DATA_JSON_PATH"] || File.join(Paths::WEB_DIR, "data.json")
OUTPUT_DIR     = ENV["OUTPUT_DIR"] || Paths::DATA_DIR
STATUSES_LIMIT = 40
# Sbírej posty jen z účtů s aspoň tolika followery. Engagementové žebříčky
# (boosty/favy) vyžadují publikum — účty bez sledujících do nich nepřispějí,
# takže je zbytečné je každý den dotazovat. 0 = bez prahu (všechny účty).
# Měřeno na 1192 objevených účtech: top dle followers drží 99,9 % veškerého
# dosahu; ~644 účtů má 20+ followers, ~548 jich má méně (z toho 131 nula).
MIN_FOLLOWERS  = (ENV["MIN_FOLLOWERS"] || "20").to_i
USER_AGENT     = "mastokatalog-collect/1.0 (+https://katalog-test.zpravobot.news; research)"
# „Obsahové" instance (boti/zprávy) — sbíráme z jejich LOKÁLNÍ timeline (vč. botů),
# mimo katalog. Posty z nich projdou stejnými žebříčky jako katalogové.
FEEDS          = CatalogConfig.read_list("feeds.txt", env_key: "FEEDS_FILE")
# Blocklist — katalog už vyřazené účty neobsahuje, ale lokální timeline „obsahových"
# instancí (FEEDS) jde mimo katalog, takže by je propustila. Filtrujeme na obou
# cestách; u katalogových účtů to navíc ušetří zbytečné API dotazy.
BLOCKED        = CatalogConfig.read_handle_set("blocklist.txt", env_key: "BLOCKLIST_FILE")

def blocked?(acct)
  BLOCKED.include?(acct.to_s.downcase)
end

def log(msg)
  puts "#{Time.now.utc.strftime('%H:%M:%S')} #{msg}"
  $stdout.flush
end

# ---------------------------------------------------------------------------
# Datum / okno dne (UTC)
# ---------------------------------------------------------------------------

# --yesterday = sbírej předchozí (uzavřený) den — vhodné pro běh krátce po půlnoci.
YESTERDAY = ARGV.include?("--yesterday")

def target_date
  if ENV["DATE_OVERRIDE"] && !ENV["DATE_OVERRIDE"].empty?
    Date.parse(ENV["DATE_OVERRIDE"])
  elsif YESTERDAY
    Time.now.utc.to_date - 1
  else
    Time.now.utc.to_date
  end
end

DAY        = target_date
DAY_START  = Time.utc(DAY.year, DAY.month, DAY.day)         # 00:00 UTC dnes
DAY_END    = DAY_START + 86_400                             # 00:00 UTC zítra
# ISO week: pozor na přelom roku — cwyear (ne year) zajistí správné W01/W52/W53.
ISO_WEEK   = format("posts_%04d_W%02d.jsonl", DAY.cwyear, DAY.cweek)

OUTPUT_PATH = File.join(OUTPUT_DIR, ISO_WEEK)
# #2: stavový soubor s posledním viděným post-id per účet (klíč "username@instance").
STATE_PATH  = File.join(OUTPUT_DIR, "collect_state.json")

# ---------------------------------------------------------------------------
# Mastodon API + text utils — sdílené v lib/mastodon_api.
# Rate limit (#3), strip_html, dominant_language jsou tam.
# ---------------------------------------------------------------------------

API = MastodonAPI.new(logger: method(:log))

def http_get(host, path)
  API.get_json(host, path)
end

def strip_html(html)
  MastodonAPI.strip_html(html)
end

# Z katalogového záznamu odvodí (instance, username, display_name, avatar, family, tags).
def account_identity(rec)
  id = rec["id"].to_s
  if id.include?("@")
    username, instance = id.split("@", 2)
  else
    # bot bez @ v id → vyparsovat z profile_url https://{instance}/@{username}
    m = rec["profile_url"].to_s.match(%r{https?://([^/]+)/@([^/?#]+)})
    return nil unless m

    instance = m[1]
    username = m[2]
  end
  {
    instance: instance,
    username: username,
    # #1: numerické Mastodon id uložené při kategorizaci (update_catalog.rb) →
    # collect přeskočí lookup. Fallback na lookup, když chybí.
    account_id: rec["mastodon_id"],
    display_name: rec["display_name"],
    avatar: rec["avatar"],
    family: rec["family"],
    tags: rec["categories"] || [],
  }
end

# ---------------------------------------------------------------------------
# Sběr
# ---------------------------------------------------------------------------

# Vrátí numerické Mastodon id účtu (lookup podle username).
def lookup_account_id(instance, username)
  acct = API.lookup(instance, username)
  acct && acct["id"]
end

# Stáhne statusy účtu a vyfiltruje ty z cílového dne (UTC).
# #2: pokud známe min_id (poslední post z minulého běhu), stáhneme jen NOVĚJŠÍ
# posty místo vždy posledních 40 a filtrování.
def fetch_day_statuses(instance, account_id, min_id = nil)
  arr = API.statuses(instance, account_id, limit: STATUSES_LIMIT, min_id: min_id)
  return [] if arr.empty?

  # Filtr na cílový den platí pořád: min_id ořízne staré, den ořízne i případné
  # zítřejší/budoucí (běh kolem půlnoci) a posty starší než DAY_START bez min_id.
  arr.select do |s|
    t = (Time.parse(s["created_at"]) rescue nil)
    t && t >= DAY_START && t < DAY_END
  end
end

# Identita účtu z lokálního statusu „obsahové" instance (nemáme katalogový rec).
def feed_acct(status, host)
  a = status["account"] || {}
  uname = a["username"].to_s
  uname = a["acct"].to_s.split("@").first if uname.empty?
  {
    instance: host,
    username: uname,
    account_id: a["id"],
    display_name: a["display_name"],
    avatar: a["avatar"],
    family: nil,
    tags: [],
  }
end

# Lokální timeline „obsahové" instance za cílový den (od nejnovějšího zpět,
# stránkování max_id; zastaví pod DAY_START). Dedup řeší volající přes `seen`.
def fetch_feed_day(host)
  out = []
  max = nil
  pages = 0
  loop do
    path = "/api/v1/timelines/public?local=true&limit=40"
    path += "&max_id=#{max}" if max
    code, arr, = API.get(host, path)
    break unless code == 200 && arr.is_a?(Array) && !arr.empty?

    pages += 1
    stop = false
    arr.each do |s|
      t = (Time.parse(s["created_at"]) rescue nil)
      next unless t
      next if t >= DAY_END          # novější než cílový den (běh kolem půlnoci)
      if t < DAY_START
        stop = true
        next
      end
      out << s
    end
    break if stop || pages > 2000    # pojistka proti nekonečnu
    max = arr.last["id"]
  end
  out
end

def build_post(status, acct)
  reblogs = status["reblogs_count"] || 0
  favs = status["favourites_count"] || 0
  media = status["media_attachments"] || []
  # Hashtagy z API pole `tags` (pole {name,url}) — spolehlivější než parsovat text.
  # Normalizace: lowercase, bez #, unikátní.
  hashtags = (status["tags"] || [])
             .map { |t| t["name"].to_s.downcase.sub(/\A#/, "") }
             .reject(&:empty?).uniq
  {
    "id" => status["id"],
    "account_username" => acct[:username],
    "account_instance" => acct[:instance],
    "account_display_name" => acct[:display_name],
    "account_avatar" => acct[:avatar],
    "account_family" => acct[:family],
    "account_tags" => acct[:tags],
    "hashtags" => hashtags,
    "content_plain" => strip_html(status["content"]), # pro hledání
    "content_html" => status["content"].to_s,          # pro klikatelné odkazy (sanitizuje frontend)
    "has_media" => !media.empty?,
    "language" => status["language"],
    "created_at" => Time.parse(status["created_at"]).utc.iso8601,
    "url" => status["url"] || status["uri"],
    "reblogs_count" => reblogs,
    "favourites_count" => favs,
    "engagement" => reblogs + favs,
  }
end

# Existující id v JSONL (deduplication napříč restarty cronu).
def existing_ids(path)
  set = {}
  return set unless File.exist?(path)

  File.foreach(path, encoding: "UTF-8") do |line|
    line = line.strip
    next if line.empty?

    begin
      set[JSON.parse(line)["id"]] = true
    rescue JSON::ParserError
      next
    end
  end
  set
end

# #2: stav posledních post-id per účet (přežívá mezi běhy).
def load_state
  return {} unless File.exist?(STATE_PATH)

  JSON.parse(File.read(STATE_PATH, encoding: "UTF-8"))
rescue JSON::ParserError
  {}
end

def save_state(state)
  File.write(STATE_PATH, JSON.pretty_generate(state))
end

def main
  unless File.exist?(DATA_JSON_PATH)
    abort("❌ Katalog nenalezen: #{DATA_JSON_PATH}")
  end

  all_accounts = JSON.parse(File.read(DATA_JSON_PATH, encoding: "UTF-8"))
  all_accounts = all_accounts.is_a?(Array) ? all_accounts : []
  # Práh followers — účty pod ním do engagementových žebříčků nepřispějí.
  accounts = if MIN_FOLLOWERS.positive?
               all_accounts.select { |r| (r["followers"] || r["followers_count"]).to_i >= MIN_FOLLOWERS }
             else
               all_accounts
             end
  skipped = all_accounts.size - accounts.size
  log("Sběr postů za den #{DAY} (UTC #{DAY_START.iso8601}–#{DAY_END.iso8601})")
  log("Účtů v katalogu: #{all_accounts.size} | sbíráno: #{accounts.size} " \
      "(práh #{MIN_FOLLOWERS}+ followers, vynecháno #{skipped}) | výstup: #{OUTPUT_PATH} | dry-run: #{DRY_RUN}")

  seen = existing_ids(OUTPUT_PATH)
  log("Existujících postů v JSONL: #{seen.size}")

  state = load_state
  log("Stav (min_id) načten pro #{state.size} účtů")

  file = DRY_RUN ? nil : File.open(OUTPUT_PATH, "a", encoding: "UTF-8")
  total_new = 0
  total_dupe = 0
  accounts_with_posts = 0
  lookups_saved = 0

  accounts.each do |rec|
    acct = account_identity(rec)
    next if acct.nil?

    state_key = "#{acct[:username]}@#{acct[:instance]}"
    next if blocked?(state_key)

    # #1: použij uložené id; lookup jen jako fallback.
    account_id = acct[:account_id]
    if account_id
      lookups_saved += 1
    else
      account_id = lookup_account_id(acct[:instance], acct[:username])
    end
    if account_id.nil?
      log("  ⚠️  lookup selhal: @#{state_key}")
      next
    end

    # #2: stáhni jen posty novější než poslední známé id.
    statuses = fetch_day_statuses(acct[:instance], account_id, state[state_key])

    new_here = 0
    max_seen_id = state[state_key]
    statuses.each do |s|
      # Sleduj nejvyšší post-id (pro příští min_id) — i u duplicit.
      max_seen_id = s["id"] if max_seen_id.nil? || s["id"].to_i > max_seen_id.to_i

      post = build_post(s, acct)
      if seen[post["id"]]
        total_dupe += 1
        next
      end
      seen[post["id"]] = true
      new_here += 1
      total_new += 1
      file&.puts(JSON.generate(post))
    end
    state[state_key] = max_seen_id if max_seen_id

    accounts_with_posts += 1 if new_here.positive?
    log("  ✅ @#{state_key}: #{new_here} nových postů") if new_here.positive?
  end

  # „Obsahové" instance (feeds.txt) — denní lokální timeline vč. botů.
  FEEDS.each do |host|
    next if host.to_s.empty?

    fstatuses = fetch_feed_day(host)
    fnew = 0
    fstatuses.each do |s|
      fa = feed_acct(s, host)
      next if blocked?("#{fa[:username]}@#{fa[:instance]}")

      post = build_post(s, fa)
      if seen[post["id"]]
        total_dupe += 1
        next
      end
      seen[post["id"]] = true
      total_new += 1
      fnew += 1
      file&.puts(JSON.generate(post))
    end
    log("  📰 feed #{host}: #{fnew} nových postů (#{fstatuses.size} ve dni)")
  end

  file&.close
  save_state(state) unless DRY_RUN
  log("")
  log("Hotovo. Nových postů: #{total_new} | duplicit přeskočeno: #{total_dupe} | " \
      "účtů s posty: #{accounts_with_posts}")
  log("Optimalizace: lookup vynechán u #{lookups_saved}/#{accounts.size} účtů (mělo uložené id)")
  log("⚠️  DRY-RUN — nezapsáno do #{OUTPUT_PATH} ani #{STATE_PATH}") if DRY_RUN
end

main if __FILE__ == $PROGRAM_NAME
