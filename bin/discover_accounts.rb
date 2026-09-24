#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# discover_accounts.rb
#
# Objevuje kandidátní účty pro katalog ze TŘÍ zdrojů:
#   1) SOCIÁLNÍ GRAF seed účtů — followers/following (reálné CZ/SK účty napříč
#      libovolnými instancemi, i velkými, kde jsou Češi 0,1 %),
#   2) lokální DIRECTORY CZ/SK instancí — jen účty se zapnutou viditelností,
#   3) lokální TIMELINE CZ/SK instancí (přes web/users.json z build_search.rb) —
#      zachytí i lidi, kteří viditelnost v adresáři nechali vypnutou a nikdo ze
#      seedů je nesleduje (24. 9. 2026: 181 aktivních lidí mimo katalog,
#      114 z nich jen na cztwitter.cz; sledující top účtů by jich našli 24).
#
# Hloubka: 1 úroveň (jen přímí followers/following seedů).
# Filtr: brána aktivity (CANDIDATE_ACTIVE_DAYS) + vyřazení botů + dedup.
#        CZ/SK rozlišení dělá až update_catalog.rb při kategorizaci.
#
# Závislosti: pouze Ruby stdlib. Spuštění:
#   ruby discover_accounts.rb
#
# ENV:
#   MASTODON_TOKEN   read-only bearer token (volitelný; per-instanci, viz pozn.)
#   MASTODON_DELAY   sekundy mezi requesty (default 1.0)
#   MAX_PER_SEED     max. účtů na jeden seed/směr (default 2000; ochrana proti
#                    obřím seedům). 0 = bez limitu.
#   OUTPUT           cesta k výstupnímu seznamu (default discovered_accounts.json)
#   CANDIDATE_ACTIVE_DAYS  brána aktivity: kandidát musí mít příspěvek do N dní
#                    (default 90 = shodné s ACTIVE_DAYS katalogu; 0 = vypnuto)
#   USERS_PATH       users.json z build_search.rb (default web/users.json)
#
# Seedy se konfigurují v konstantě SEEDS níže:
#   :acct       handle ve tvaru "username@home_instance"
#   :directions :followers / :following / obojí — co z účtu stáhnout
# =============================================================================

require "json"
require "uri"
require "date"
require_relative "../lib/config"        # config.env do ENV
require_relative "../lib/mastodon_api"  # HTTP + rate limit + stránkování

MASTODON_TOKEN = ENV["MASTODON_TOKEN"]
MASTODON_DELAY = (ENV["MASTODON_DELAY"] || "1.0").to_f
MAX_PER_SEED   = (ENV["MAX_PER_SEED"] || "2000").to_i
OUTPUT         = ENV["OUTPUT"] || File.join(Paths::DATA_DIR, "discovered_accounts.json")

# Seed účty (seeds.txt) — z koho brát followers/following.
# Formát řádku: "username@instance  directions" (directions čárkou; viz seeds.txt).
SEEDS = CatalogConfig.read_list("seeds.txt", env_key: "SEEDS_FILE").map do |line|
  acct, dirs = line.split(/\s+/, 2)
  directions = (dirs.to_s.empty? ? "followers" : dirs).split(",").map { |d| d.strip.to_sym }
  { acct: acct, directions: directions }
end.freeze

# CZ/SK instance (instances.txt) — scrapujeme jejich /api/v1/directory (lokální účty).
INSTANCES = CatalogConfig.read_list("instances.txt", env_key: "INSTANCES_FILE").freeze
# Mrtvé/zaniklé instance — účty z nich vůbec nepřidáváme (federovaný graf je drží
# jako „duchy"; jinak by zbytečně zahltily kandidáty a v update jen timeoutovaly).
DEAD_INSTANCES = CatalogConfig.read_list("dead_instances.txt", env_key: "DEAD_INSTANCES_FILE")
                              .map(&:downcase).freeze

# Kolik účtů max z jednoho directory (0 = bez limitu).
MAX_PER_DIRECTORY = (ENV["MAX_PER_DIRECTORY"] || "0").to_i

# Brána aktivity: kandidát musí mít příspěvek do N dní. Sledující velkých účtů
# jsou z většiny čtenáři, ne pisatelé — změřeno 24. 9. 2026: z 5 708 nových
# sledujících šesti nejsledovanějších účtů psalo za 90 dní jen 1 122. Bez brány
# by zbytek katalog jen nafoukl a každý účet z .cz/.sk instance by navíc prošel
# placenou AI kategorizací (update_catalog.rb podle počtu postů nefiltruje).
# Odpověď followers/directory nese `last_status_at` i `statuses_count`, takže
# brána nestojí ani jeden dotaz navíc. Pozor: u sledujících jde o federovanou
# kopii účtu na instanci seedu, datum tam může být o něco pozadu — brána je
# proto předvýběr, ověření dělá update_catalog.rb lookupem na domovské instanci.
CANDIDATE_ACTIVE_DAYS = (ENV["CANDIDATE_ACTIVE_DAYS"] || "90").to_i

# Lokální timeline CZ/SK instancí (zdroj 3): build_search.rb je stahuje každých
# 6 h a účty, které na nich psaly, ukládá do web/users.json — i ty mimo katalog
# (`cat: false`). Odtud je bereme; discovery tak nestahuje nic podruhé.
USERS_PATH = ENV["USERS_PATH"] || File.join(Paths::WEB_DIR, "users.json")

STATS = Hash.new(0) # inactive: kolik kandidátů brána aktivity vyřadila

def log(msg)
  puts "#{Time.now.strftime('%H:%M:%S')} #{msg}"
  $stdout.flush
end

# ---------------------------------------------------------------------------
# Mastodon API — sdílené v lib/mastodon_api (HTTP, rate limit, stránkování).
# ---------------------------------------------------------------------------

API = MastodonAPI.new(logger: method(:log), delay: MASTODON_DELAY, token: MASTODON_TOKEN)

# Normalizuje acct na "username@home_instance" (Mastodon u lokálních účtů
# vrací `acct` bez domény → doplníme domácí instanci, na které jsme se ptali).
def full_acct(account, queried_host)
  a = account["acct"].to_s
  a.include?("@") ? a : "#{a}@#{queried_host}"
end

# ---------------------------------------------------------------------------
# Lookup seedu → id
# ---------------------------------------------------------------------------

def lookup_id(host, username)
  acct = API.lookup(host, username)
  return acct["id"] if acct

  log("  ❌ lookup #{username}@#{host} selhal")
  nil
end

# Má kandidát nedávný příspěvek? `last_status_at` do `window` dní. Chybějící
# datum znamená u Mastodonu „nikdy nepublikoval" — jenže Pixelfed ho nevrací
# vůbec (nil i při stovkách postů), proto tam rozhoduje `statuses_count`.
# window <= 0 bránu vypíná.
def recently_active?(acc, today: Date.today, window: CANDIDATE_ACTIVE_DAYS)
  return true if window <= 0

  last = acc["last_status_at"].to_s[0, 10]
  return acc["statuses_count"].to_i.positive? if last.empty?

  (today - Date.parse(last)).to_i <= window
rescue ArgumentError
  false
end

# Přidá účet do `into` (dedup dle full_acct, boty a neaktivní vynechá). Vrací
# true pokud byl započítán (i duplicita se počítá do limitu/průchodu).
def add_account(into, acc, host)
  return false if acc["bot"]

  key = full_acct(acc, host)
  inst = key.split("@").last.to_s.downcase
  return false if DEAD_INSTANCES.include?(inst) || MastodonAPI.bridge?(inst)
  unless recently_active?(acc)
    STATS[:inactive] += 1
    return false
  end

  into[key] ||= {
    "acct" => key,
    "username" => acc["username"],
    "instance" => key.split("@").last,
    "display_name" => acc["display_name"],
    "followers_count" => acc["followers_count"],
    "statuses_count" => acc["statuses_count"],
    "bot" => false,
  }
  true
end

# ---------------------------------------------------------------------------
# Stažení jednoho směru (followers/following) se stránkováním (Link hlavička)
# ---------------------------------------------------------------------------

def fetch_direction(host, account_id, direction, into)
  path = "/api/v1/accounts/#{account_id}/#{direction}?limit=80"
  count = 0
  loop do
    code, arr, link = API.get(host, path)
    break unless code == 200 && arr.is_a?(Array) && !arr.empty?

    arr.each { |acc| count += 1 if add_account(into, acc, host) }
    break if MAX_PER_SEED.positive? && count >= MAX_PER_SEED

    max_id = MastodonAPI.next_max_id(link)
    break unless max_id

    path = "/api/v1/accounts/#{account_id}/#{direction}?limit=80&max_id=#{max_id}"
  end
  count
end

# ---------------------------------------------------------------------------
# Stažení lokálního directory instance se stránkováním (offset)
# ---------------------------------------------------------------------------

def fetch_directory(host, into)
  offset = 0
  count = 0
  loop do
    code, arr, = API.get(host, "/api/v1/directory?limit=80&offset=#{offset}&local=true&order=active")
    break unless code == 200 && arr.is_a?(Array) && !arr.empty?

    arr.each { |acc| count += 1 if add_account(into, acc, host) }
    break if MAX_PER_DIRECTORY.positive? && count >= MAX_PER_DIRECTORY

    offset += arr.size
  end
  count
end

# ---------------------------------------------------------------------------
# Kandidáti z lokálních timeline (users.json z build_search.rb)
# ---------------------------------------------------------------------------

# Z položek users.json vybere účty mimo katalog (`cat: false`) s příspěvkem do
# `window` dní a převede je na tvar kandidáta. Boty nerozliší (users.json
# příznak nenese) — vyřadí je až update_catalog.rb při lookupu, stejně jako
# u ostatních zdrojů. Čistá funkce — testuje se v test/test_discover.rb.
def timeline_candidates(users, today: Date.today, window: CANDIDATE_ACTIVE_DAYS, dead: DEAD_INSTANCES)
  Array(users).filter_map do |u|
    next unless u.is_a?(Hash) && !u["cat"]

    acct = u["a"].to_s.delete_prefix("@")
    username, instance = acct.split("@", 2)
    next if username.to_s.empty? || instance.to_s.empty?
    next if dead.include?(instance.downcase) || MastodonAPI.bridge?(instance)
    next unless recently_active?({ "last_status_at" => u["last"] }, today: today, window: window)

    {
      "acct" => acct,
      "username" => username,
      "instance" => instance,
      "display_name" => u["n"],
      "followers_count" => u["fo"],
      "statuses_count" => u["np"],
      "bot" => false,
    }
  end
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main
  log("Objevování účtů | seedů=#{SEEDS.size} | instancí=#{INSTANCES.size} | token=#{MASTODON_TOKEN ? 'ano' : 'ne'}")
  abort("❌ Prázdné seedy i instance — vyplň seeds.txt nebo instances.txt") if SEEDS.empty? && INSTANCES.empty?
  discovered = {} # full_acct => záznam

  # 1) Sociální graf seedů (followers/following)
  SEEDS.each do |seed|
    username, host = seed[:acct].split("@", 2)
    log("──────── seed @#{seed[:acct]} ────────")
    id = lookup_id(host, username)
    next unless id

    seed[:directions].each do |dir|
      before = discovered.size
      n = fetch_direction(host, id, dir, discovered)
      added = discovered.size - before
      log("  #{dir}: prošlo #{n}, nově přidáno #{added} (po dedup/bez botů)")
    end
  end

  # 2) Lokální directory CZ/SK instancí (účty mimo seed graf)
  INSTANCES.each do |host|
    before = discovered.size
    n = fetch_directory(host, discovered)
    added = discovered.size - before
    log("──────── directory #{host} ──────── prošlo #{n}, nově #{added}")
  end

  # 3) Lokální timeline CZ/SK instancí — účty, které tam psaly, ale directory
  #    je nevydá (vypnutá viditelnost) a seedy je nesledují.
  if File.exist?(USERS_PATH)
    users = begin
      JSON.parse(File.read(USERS_PATH, encoding: "UTF-8"))
    rescue JSON::ParserError => e
      log("  ⚠️  #{USERS_PATH}: #{e.message} → zdroj timeline přeskočen")
      []
    end
    users = users.values.find { |v| v.is_a?(Array) } || [] if users.is_a?(Hash)
    before = discovered.size
    tl = timeline_candidates(users)
    tl.each { |c| discovered[c["acct"]] ||= c }
    log("──────── timeline (#{File.basename(USERS_PATH)}) ──────── mimo katalog a aktivní #{tl.size}, nově #{discovered.size - before}")
  else
    log("──────── timeline ──────── #{USERS_PATH} chybí (build_search.rb ještě neběžel) → zdroj přeskočen")
  end

  result = discovered.values.sort_by { |r| r["acct"] }
  File.write(OUTPUT, JSON.pretty_generate(result))

  by_instance = result.group_by { |r| r["instance"] }
                      .transform_values(&:size)
                      .sort_by { |_, n| -n }
  log("")
  log("✅ Objeveno unikátních ne-bot účtů: #{result.size}")
  log("   Brána aktivity (#{CANDIDATE_ACTIVE_DAYS} dní) vyřadila #{STATS[:inactive]} účtů bez nedávného příspěvku") if CANDIDATE_ACTIVE_DAYS.positive?
  log("Top instance:")
  by_instance.first(12).each { |inst, n| log("  #{inst}: #{n}") }
  log("Zapsáno #{OUTPUT}")
  log("→ Tento seznam je vstup pro cílený lookup + AI kategorizaci (mimo PoC běh).")
end

main if __FILE__ == $PROGRAM_NAME
