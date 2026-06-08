#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# discover_accounts.rb
#
# Objevuje kandidátní účty pro katalog ze SOCIÁLNÍHO GRAFU seed účtů.
# Místo prohrabávání directory velkých instancí (kde jsou Češi 0,1 %) vyjde
# z konkrétních seedů a stáhne jejich followers/following — to jsou reálné
# CZ/SK účty napříč libovolnými instancemi (mastodon.social, mamutovo.cz, …).
#
# Hloubka: 1 úroveň (jen přímí followers/following seedů).
# Filtr: žádný CZ/SK filtr zde — jen vyřadí boty a deduplikuje. CZ/SK rozlišení
#        dělá až update_catalog.rb při kategorizaci.
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
#
# Seedy se konfigurují v konstantě SEEDS níže:
#   :acct       handle ve tvaru "username@home_instance"
#   :directions :followers / :following / obojí — co z účtu stáhnout
# =============================================================================

require "json"
require "uri"
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

# Přidá účet do `into` (dedup dle full_acct, boty vynechá). Vrací true pokud
# byl započítán (i duplicita se počítá do limitu/průchodu).
def add_account(into, acc, host)
  return false if acc["bot"]

  key = full_acct(acc, host)
  inst = key.split("@").last.to_s.downcase
  return false if DEAD_INSTANCES.include?(inst) || MastodonAPI.bridge?(inst)
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

  result = discovered.values.sort_by { |r| r["acct"] }
  File.write(OUTPUT, JSON.pretty_generate(result))

  by_instance = result.group_by { |r| r["instance"] }
                      .transform_values(&:size)
                      .sort_by { |_, n| -n }
  log("")
  log("✅ Objeveno unikátních ne-bot účtů: #{result.size}")
  log("Top instance:")
  by_instance.first(12).each { |inst, n| log("  #{inst}: #{n}") }
  log("Zapsáno #{OUTPUT}")
  log("→ Tento seznam je vstup pro cílený lookup + AI kategorizaci (mimo PoC běh).")
end

main if __FILE__ == $PROGRAM_NAME
