#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# bin/build_search.rb — batch pro vyhledávání postů + účtů (slonik.online).
#
# Zdroje: (1) lokální veřejné timeline CZ/SK instancí (config/instances.txt),
#         (2) katalogové účty (web/data.json) na neskrapovaných instancích
#             (pokrytí lidí na mastodon.social ap.) — pokud není --no-catalog.
#
# Výstup (klient hledá v prohlížeči, deterministicky, bez backendu/LLM):
#   web/search.json — posty v posts.json schématu (+ content_folded pro hledání)
#   web/users.json  — účty = autoři postů ∪ katalog (+ folded pole `f`)
#
# Posty mají schéma jako posts.json → frontend je vykreslí stejnou kartou
# (buildPostCard). Účty rovněž (buildCard). Žádná lemmatizace/synonyma (fáze 0).
#
# Přírůstkově: navazuje na existující index + stav (data/search_state.json) —
# stáhne jen posty novější než poslední běh, dedupne, vyřadí starší než retence.
# První běh / --rebuild = plné stažení do retence.
#
# Spuštění:
#   ruby bin/build_search.rb                 # přírůstkově (denní cron), upload
#   ruby bin/build_search.rb --rebuild       # plný build od nuly
#   RETENTION_DAYS=7 ruby bin/build_search.rb
#   ruby bin/build_search.rb --no-catalog --no-upload
# ENV: RETENTION_DAYS (30), MASTODON_DELAY.
# =============================================================================

require "json"
require "time"
require "date"
require "set"
require_relative "../lib/config"
require_relative "../lib/mastodon_api"

RETENTION_DAYS = (ENV["RETENTION_DAYS"] || "30").to_i
# „Obsahové" instance (feeds.txt — boti/zprávy) indexujeme s kratší retencí,
# ať velký objem nenafoukne search.json. 30 dní pro běžné, 7 pro feeds.
FEEDS_RETENTION_DAYS = (ENV["FEEDS_RETENTION_DAYS"] || "7").to_i
NO_CATALOG     = ARGV.include?("--no-catalog")
REBUILD        = ARGV.include?("--rebuild")   # ignoruj stav i existující index (plný build)
CUTOFF         = Time.now.utc - RETENTION_DAYS * 86_400
FEEDS_CUTOFF   = Time.now.utc - FEEDS_RETENTION_DAYS * 86_400
# Okno obnovy počtů. Přírůstkový build bere jen posty novější než poslední viděné
# id, takže post zaindexovaný pár minut po publikaci si svoje nuly nese celou dobu
# retence — a Skokani ve Vyhledávání se z těch čísel počítají. Posty mladší než
# REFRESH_DAYS proto projdeme znovu i tehdy, když už v indexu jsou; většina boostů
# a oblíbených přijde právě v těch prvních dnech. Neplatíme za to zvlášť — čísla
# přijdou v týchž stránkách timeline, jen se u nich nezastavíme dřív.
REFRESH_DAYS       = (ENV["SEARCH_REFRESH_DAYS"] || "2").to_i
FEEDS_REFRESH_DAYS = (ENV["FEEDS_REFRESH_DAYS"] || "1").to_i
REFRESH_CUTOFF       = Time.now.utc - REFRESH_DAYS * 86_400
FEEDS_REFRESH_CUTOFF = Time.now.utc - FEEDS_REFRESH_DAYS * 86_400
OUT_PATH       = File.join(Paths::WEB_DIR, "search.json")
USERS_PATH     = File.join(Paths::WEB_DIR, "users.json")
CATALOG_PATH   = Paths.catalog_source   # interní úložiště (má mastodon_id), fallback web/data.json
STATE_PATH     = File.join(Paths::DATA_DIR, "search_state.json")
STATUS_PATH    = File.join(Paths::WEB_DIR, "status.json")   # malý meta soubor pro patičku

# Zapíše/sloučí čas poslední indexace do web/status.json (patička webu).
def write_status
  status = (JSON.parse(File.read(STATUS_PATH, encoding: "UTF-8")) rescue {})
  status = {} unless status.is_a?(Hash)
  status["search_indexed"] = Time.now.utc.iso8601
  File.write("#{STATUS_PATH}.tmp", JSON.generate(status))
  File.rename("#{STATUS_PATH}.tmp", STATUS_PATH)
end

def log(msg)
  puts "#{Time.now.strftime('%H:%M:%S')} #{msg}"
  $stdout.flush
end

API = MastodonAPI.new(logger: method(:log))

# Blocklist (blocklist.txt) — účty, které si vyžádaly odstranění, nebo je vyřadil
# kurátor. Katalog je řeší v update_catalog.rb, ale index vyhledávání si posty tahá
# z LOKÁLNÍCH TIMELINE instancí, tedy úplně mimo katalog — bez tohohle filtru by
# vyřazený účet dál visel ve Vyhledávání i v users.json. Filtr se uplatní i na už
# postavený index, takže odstranění zabere hned při dalším přírůstkovém běhu.
BLOCKED = CatalogConfig.read_handle_set("blocklist.txt", env_key: "BLOCKLIST_FILE")

def blocked?(acct)
  BLOCKED.include?(acct.to_s.downcase)
end

STATS = Hash.new(0)

# Kadence individuálního pollingu katalogových účtů (ty na neskrapovaných
# instancích, které lokální timeline nepokryje). Aktivní účet dotazujeme každý
# běh, mlčící jednou za SEARCH_POLL_INACTIVE_DAYS — dvě třetiny tohohle seznamu
# tvoří účty bez příspěvku přes 90 dní, u kterých 4 dotazy denně nic nepřinesou.
# Nepolníme je NIKDY — jen zřídka, ať se návrat k psaní pozná.
ACTIVE_DAYS               = (ENV["ACTIVE_DAYS"] || "90").to_i
SEARCH_POLL_INACTIVE_DAYS = (ENV["SEARCH_POLL_INACTIVE_DAYS"] || "7").to_i

def days_since(iso)
  return nil if iso.to_s.empty?

  (Date.today - Date.parse(iso.to_s)).to_i
rescue ArgumentError
  nil
end

# Má se katalogový účet v tomhle běhu pollovat individuálně?
def due_poll?(rec)
  d = days_since(rec["last_status_at"])
  return true if d && d <= ACTIVE_DAYS

  last = STATE["poll:#{rec['id']}"]
  return true if last.nil?

  (days_since(last) || SEARCH_POLL_INACTIVE_DAYS) >= SEARCH_POLL_INACTIVE_DAYS
end

# Přírůstkový stav: zdroj (tl:<host> / acct:<id>) => poslední viděné status id.
STATE = if REBUILD || !File.exist?(STATE_PATH)
          {}
        else
          (JSON.parse(File.read(STATE_PATH, encoding: "UTF-8")) rescue {})
        end
NEW_STATE = STATE.dup

def fold(str)
  # NFKD → bez diakritiky → lowercase → mezery/zalomení sjednotit (kvůli frázím).
  str.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.gsub(/\s+/, " ").strip
end

# Katalog (data.json) → mapa acct => záznam (pro propsání facetů a do users).
def catalog_map
  return {} unless File.exist?(CATALOG_PATH)

  JSON.parse(File.read(CATALOG_PATH, encoding: "UTF-8"))
      .select { |r| r["id"].to_s.include?("@") && !blocked?(r["id"]) }
      .to_h { |r| [r["id"], r] }
rescue StandardError
  {}
end

# Mastodon status → minimální záznam pro index. Text neukládáme 3× — držíme jen
# `content_html`; `content_plain` a `content_folded` dopočítá frontend při načtení
# (menší search.json). Autorská pole zůstávají (potřebuje je build_users i purge).
def record(status, instance)
  return nil if status["reblog"]

  acct = status["account"] || {}
  plain = MastodonAPI.strip_html(status["content"].to_s).strip
  return nil if plain.empty?

  user = acct["acct"].to_s
  user = "#{user}@#{instance}" unless user.include?("@")
  return nil if blocked?(user)

  name = acct["display_name"].to_s.empty? ? acct["username"].to_s : acct["display_name"]
  {
    "id" => "#{instance}:#{status['id']}",
    "url" => status["url"] || status["uri"],
    "account_username" => user.split("@").first,
    "account_instance" => instance,
    "account_acct" => user,
    "account_display_name" => name,
    "account_avatar" => acct["avatar"],
    "account_followers" => acct["followers_count"] || 0,
    "created_at" => status["created_at"],
    "content_html" => status["content"].to_s,   # klikatelné odkazy/hashtagy/mentions (sanitizuje frontend)
    "reblogs_count" => status["reblogs_count"] || 0,
    "favourites_count" => status["favourites_count"] || 0,
    "engagement" => (status["reblogs_count"] || 0) + (status["favourites_count"] || 0),
    "has_media" => !Array(status["media_attachments"]).empty?,
    "hashtags" => Array(status["tags"]).map { |t| t["name"] }.compact,
    "language" => status["language"],
  }
end

# Slim post pro search.json — autorská pole (kromě account_acct) frontend dopočítá:
# username/instance z acct, jméno/avatar z users.json. Nepíšeme je tedy do každého
# postu (u chrličů jako zpravobot se jinak avatar/jméno opakují tisíckrát).
SLIM_KEYS = %w[id url account_acct account_family content_html
               reblogs_count favourites_count created_at has_media hashtags].freeze
def slim_post(p)
  SLIM_KEYS.each_with_object({}) { |k, h| h[k] = p[k] if p.key?(k) }
end

# Přírůstkové stránkování: od nejnovějšího zpět; bere posty NOVĚJŠÍ než poslední
# viděné id daného zdroje (STATE) a zároveň ≥ CUTOFF. První běh (bez stavu) =
# plné stažení do CUTOFF. Aktualizuje NEW_STATE na nejnovější viděné id.
def paginate(host, base_path, seen, source_key, cutoff = CUTOFF, refresh_cutoff = REFRESH_CUTOFF)
  last = (STATE[source_key] || "0").to_i
  newest = last
  reachable = false
  path = base_path
  loop do
    code, arr, link = API.get(host, path)
    reachable = true if code == 200
    break unless code == 200 && arr.is_a?(Array) && !arr.empty?

    stop = false
    arr.each do |s|
      sid = s["id"].to_i
      newest = sid if sid > newest
      ts = (Time.parse(s["created_at"]) rescue Time.now.utc)
      if ts < cutoff
        stop = true
        next
      end
      # Už indexovaný a zároveň starší než okno obnovy → dál zpět nemá smysl jít.
      # (Jen `sid <= last` by nás zastavilo hned u prvního známého postu, takže by
      # se počty nikdy neobnovily.)
      if sid <= last && ts < refresh_cutoff
        stop = true
        next
      end
      rec = record(s, host)
      next unless rec

      if (known = seen[rec["id"]])
        # Post už v indexu je — obnovíme jen to, co se v čase mění.
        next if known["reblogs_count"] == rec["reblogs_count"] &&
                known["favourites_count"] == rec["favourites_count"]

        known["reblogs_count"]    = rec["reblogs_count"]
        known["favourites_count"] = rec["favourites_count"]
        known["engagement"]       = rec["engagement"]
        STATS[:refreshed] += 1
      else
        seen[rec["id"]] = rec
      end
    end
    break if stop

    mid = MastodonAPI.next_max_id(link)
    break unless mid

    sep = base_path.include?("?") ? "&" : "?"
    path = "#{base_path}#{sep}max_id=#{mid}"
  end
  NEW_STATE[source_key] = newest.to_s if newest.positive?
  reachable
end

# Účty = autoři postů (ze `seen`) ∪ katalog. Katalogové účty: bohatá metadata
# (avatar, oblast/family, typ, followers) a jsou v indexu i bez postů v okně.
def build_users(seen, cat)
  users = {}
  seen.each_value do |p|
    a = p["account_acct"]
    u = users[a] ||= { "a" => a, "n" => p["account_display_name"], "i" => p["account_instance"],
                       "av" => p["account_avatar"], "fo" => p["account_followers"], "np" => 0, "last" => p["created_at"] }
    u["np"] += 1
    u["last"] = p["created_at"] if p["created_at"].to_s > u["last"].to_s
  end
  cat.each do |acct, c|
    u = users[acct] ||= { "a" => acct, "n" => (c["display_name"].to_s.empty? ? acct.split("@").first : c["display_name"]),
                          "i" => acct.split("@", 2).last, "av" => c["avatar"], "fo" => c["followers"], "np" => 0, "last" => nil }
    u["cat"] = true
    u["ob"]  = c["family"]
    u["ty"]  = c["type"]
    u["av"]  ||= c["avatar"]
    u["fo"]  = c["followers"] if c["followers"]
    u["_bio"]  = MastodonAPI.strip_html(c["bio"].to_s)
    u["_tags"] = Array(c["categories"]).join(" ")
  end
  users.each_value do |u|
    extra = u["cat"] ? " #{u['_bio']} #{u['_tags']}" : ""
    u["f"] = fold("#{u['n']} #{u['a']}#{extra}")
    u.delete("_bio"); u.delete("_tags")
  end
  users.values.sort_by { |u| -(u["fo"] || 0) }
end

def main
  mode = REBUILD ? "PLNÝ (--rebuild)" : "přírůstkový"
  log("Build search | retence #{RETENTION_DAYS} dní (od #{CUTOFF.strftime('%Y-%m-%d')}) | #{mode} | " \
      "katalog=#{!NO_CATALOG} | blocklist=#{BLOCKED.size}")
  instances = CatalogConfig.read_list("instances.txt", env_key: "INSTANCES_FILE")
  feeds = CatalogConfig.read_list("feeds.txt", env_key: "FEEDS_FILE")
  feeds_set = feeds.to_set
  seen = {}

  # Cutoff pro daný post: feeds (boti) mají kratší retenci než běžné instance.
  # Instanci bereme z account_acct (slim index nemusí mít account_instance pole).
  inst_of     = ->(p) { (p["account_instance"] || p["account_acct"].to_s.split("@").last).to_s }
  post_cutoff = ->(p) { feeds_set.include?(inst_of.call(p)) ? FEEDS_CUTOFF : CUTOFF }

  # Základ = existující (slim) index (mimo --rebuild); rovnou vyřaď posty starší než
  # retence. Autorská pole dotáhneme z users.json + odvodíme z acct, ať je build_users
  # i facety mají v paměti k dispozici (na disku už v každém postu nejsou).
  if !REBUILD && File.exist?(OUT_PATH)
    base_users = {}
    if File.exist?(USERS_PATH)
      (JSON.parse(File.read(USERS_PATH, encoding: "UTF-8"))["users"] rescue []).each { |u| base_users[u["a"]] = u }
    end
    old = (JSON.parse(File.read(OUT_PATH, encoding: "UTF-8"))["posts"] rescue [])
    dropped_blocked = 0
    old.each do |p|
      a = p["account_acct"].to_s
      if blocked?(a)   # účet přibyl do blocklistu → vypadne i ze starého indexu
        dropped_blocked += 1
        next
      end
      p["account_username"] ||= a.split("@").first
      p["account_instance"] ||= a.split("@", 2)[1]
      if (u = base_users[a])
        p["account_display_name"] ||= u["n"]
        p["account_avatar"]       ||= u["av"]
        p["account_followers"]    ||= u["fo"]
      end
      seen[p["id"]] = p if (Time.parse(p["created_at"]) rescue Time.at(0)) >= post_cutoff.call(p)
    end
    log("  Základ z existujícího indexu: #{seen.size} postů (v retenci)")
    log("  🚫 Odebráno postů z blocklistu: #{dropped_blocked}") if dropped_blocked.positive?
  end

  scraped = instances.to_set
  failed = Set.new   # scrapované instance, jejichž timeline selhala (lokál nedostupný)

  log("── Lokální timeline (#{instances.size} instancí) ──")
  instances.each do |host|
    before = seen.size
    ok = paginate(host, "/api/v1/timelines/public?local=true&limit=40", seen, "tl:#{host}")
    failed << host unless ok
    n = seen.size - before
    log("  #{host}: +#{n}#{ok ? '' : ' (nedostupné → katalog individuálně)'}") if n.positive? || !ok
  end

  # „Obsahové" instance (feeds.txt) — boti/zprávy do vyhledávání, kratší retence.
  unless feeds.empty?
    log("── Obsahové instance / feeds (#{feeds.size}, retence #{FEEDS_RETENTION_DAYS} dní) ──")
    feeds.each do |host|
      before = seen.size
      paginate(host, "/api/v1/timelines/public?local=true&limit=40", seen, "feed:#{host}",
               FEEDS_CUTOFF, FEEDS_REFRESH_CUTOFF)
      log("  #{host}: +#{seen.size - before}")
    end
  end

  cat = catalog_map
  unless NO_CATALOG
    # Katalogové účty pollujeme individuálně jen tam, kde je timeline nepokryje:
    # na NEscrapovaných instancích, nebo na scrapovaných s nedostupnou timeline.
    uncovered = cat.values.select do |c|
      inst = c["id"].split("@", 2).last
      !scraped.include?(inst) || failed.include?(inst)
    end
    todo = uncovered.select { |c| due_poll?(c) }
    log("── Katalogové účty individuálně: #{todo.size} z #{uncovered.size} (mimo dostupné lokály; " \
        "mlčící á #{SEARCH_POLL_INACTIVE_DAYS} dní) ──")
    before = seen.size
    todo.each_with_index do |c, i|
      username, instance = c["id"].split("@", 2)
      mid = c["mastodon_id"] || (API.lookup(instance, username)&.dig("id"))
      next unless mid

      paginate(instance, "/api/v1/accounts/#{mid}/statuses?limit=40&exclude_reblogs=true", seen, "acct:#{c['id']}")
      NEW_STATE["poll:#{c['id']}"] = Date.today.to_s
      log("  …#{i + 1}/#{todo.size}") if ((i + 1) % 50).zero?
    end
    log("  Po katalogu: +#{seen.size - before} postů")

    # Prořež stav pollingu u účtů, které už v katalogu nejsou (jinak by rostl donekonečna).
    NEW_STATE.delete_if { |k, _| k.start_with?("poll:") && !cat.key?(k.delete_prefix("poll:")) }
  end

  # Propsání katalogových facetů na posty (oblast/tagy) — odlišovač vs. Mastodon.
  seen.each_value do |p|
    c = cat[p["account_acct"]]
    next unless c

    p["account_family"] = c["family"]
    p["account_tags"] = c["categories"]
  end

  posts = seen.values.sort_by { |r| r["created_at"].to_s }.reverse
  # build_users čte plné záznamy (seen) — proto users.json sestavíme PŘED slim zápisem.
  users = build_users(seen, cat)

  slim = posts.map { |p| slim_post(p) }
  File.write("#{OUT_PATH}.tmp", JSON.generate({ "generated_at" => Time.now.utc.iso8601,
                                                "retention_days" => RETENTION_DAYS, "count" => slim.size, "posts" => slim }))
  File.rename("#{OUT_PATH}.tmp", OUT_PATH)
  log("✅ Posty: #{slim.size} → #{OUT_PATH} (#{(File.size(OUT_PATH) / 1_048_576.0).round(2)} MB)")
  log("   Obnoveno počtů (boosty/oblíbení) u #{STATS[:refreshed]} už indexovaných postů " \
      "— okno #{REFRESH_DAYS} dní (feeds #{FEEDS_REFRESH_DAYS})")

  File.write("#{USERS_PATH}.tmp", JSON.generate({ "generated_at" => Time.now.utc.iso8601, "count" => users.size, "users" => users }))
  File.rename("#{USERS_PATH}.tmp", USERS_PATH)
  log("✅ Účty: #{users.size} (katalog #{users.count { |u| u['cat'] }}) → #{USERS_PATH} (#{(File.size(USERS_PATH) / 1024.0).round} KB)")

  # Přírůstkový stav (poslední id per zdroj) — příští běh stáhne jen novější.
  File.write("#{STATE_PATH}.tmp", JSON.generate(NEW_STATE))
  File.rename("#{STATE_PATH}.tmp", STATE_PATH)

  write_status   # čas indexace do web/status.json (patička)

  if ARGV.include?("--no-upload")
    log("⏭  --no-upload → ponecháno jen lokálně.")
  else
    Surfer.upload(OUT_PATH, logger: method(:log))
    Surfer.upload(USERS_PATH, logger: method(:log))
    Surfer.upload(STATUS_PATH, logger: method(:log))
  end
end

main if __FILE__ == $PROGRAM_NAME
