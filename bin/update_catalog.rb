#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# update_catalog.rb — inkrementální aktualizace katalogu.
#
# Udržuje data.json živý, aniž by se vše kategorizovalo (a platilo) znovu:
#   1. Načte stávající data.json a zdroj kandidátů (discovered_accounts.json).
#   2. Rozdělí: NOVÉ účty (nejsou v katalogu) vs. STÁVAJÍCÍ.
#   3. NOVÉ → zkategorizuje přes Claude API (platí se jen za ně).
#   4. STÁVAJÍCÍ → refresh metrik (followers/avatar/bio) přes Mastodon lookup,
#      BEZ AI (rodina/tagy/popis zůstávají — zdarma).
#   5. Sloučí, zapíše data.json (se zálohou) a nahraje na Surfer.
#
# Spuštění:
#   ANTHROPIC_API_KEY=... ruby update_catalog.rb       # plná aktualizace
#   ruby update_catalog.rb --dry-run                   # jen diff + odhad ceny
#   ruby update_catalog.rb --no-categorize             # nové jen vypíše (bez AI)
#   ruby update_catalog.rb --no-refresh                # bez refreshe stávajících
#   ruby update_catalog.rb --refresh-all               # obnov i mlčící (mimo kadenci)
#   ruby update_catalog.rb --no-upload                 # nenahrávat na Surfer
#   ruby update_catalog.rb --no-czsk-filter            # kategorizovat i ne-CZ/SK
#   ruby update_catalog.rb --recheck-skipped           # ignoruj cache přeskočených
#   ruby update_catalog.rb --retype                    # přeznač type u aktivních (bio-only, levné)
#   ruby update_catalog.rb --refamily                  # přeznač family u aktivních v koši „lifestyle"
#
# ENV: ANTHROPIC_API_KEY, AI_MODEL, AI_DELAY, MASTODON_DELAY, MASTODON_TOKEN,
#      ACTIVE_DAYS (90), CATALOG_PATH (web/data.json),
#      CANDIDATES_PATH (data/discovered_accounts.json),
#      SKIPPED_PATH (skipped_noncz.json), MANUAL_FILE (manual_accounts.txt),
#      BLOCKLIST_FILE (blocklist.txt), STATUSES_LIMIT (20),
#      LIMIT_NEW (0 = bez limitu), FLUSH_EVERY (25 = lokální checkpoint po N účtech),
#      UPLOAD_EVERY (250 = průběžný upload na Surfer po N účtech; 0 = jen na konci),
#      SURFER_* (viz config.env).
# =============================================================================

require "json"
require "set"
require "date"
require "time"
require_relative "../lib/config"        # config.env do ENV + Surfer.upload
require_relative "../lib/mastodon_api"
require_relative "../lib/ai"
require_relative "../lib/catalog"

DRY_RUN         = ARGV.include?("--dry-run")
NO_CATEGORIZE   = ARGV.include?("--no-categorize")
NO_REFRESH      = ARGV.include?("--no-refresh")
NO_UPLOAD       = ARGV.include?("--no-upload")
RECHECK_SKIPPED = ARGV.include?("--recheck-skipped") # ignoruj cache přeskočených
RETYPE          = ARGV.include?("--retype")          # přeznač type u aktivních účtů
REFAMILY        = ARGV.include?("--refamily")        # přeznač family u aktivních v koši „lifestyle"
# Rodiny, které --refamily bere jako „k přeznačení". Default je koš `lifestyle`
# — dokud rodina `local` neměla vlastní mapování (viz AI::FAMILY_MAP), padaly
# do něj i regionální účty a nešly od nezařaditelných odlišit.
REFAMILY_FROM   = (ENV["REFAMILY_FROM"] || "lifestyle").split(",").map(&:strip).reject(&:empty?)

# Interní úložiště katalogu (plné záznamy) vs. publikovaný payload (jen pole,
# která frontend vykresluje). Viz Paths.
CATALOG_PATH    = ENV["CATALOG_PATH"] || Paths::CATALOG_STORE
PUBLIC_PATH     = ENV["PUBLIC_CATALOG_PATH"] || Paths::CATALOG_PUBLIC
# Seznam publikovaných polí drží lib/catalog.rb — sdílí ho i cache_avatars.rb.
PUBLIC_KEYS = Catalog::PUBLIC_KEYS
STATUS_PATH     = ENV["STATUS_PATH"] || File.join(Paths::WEB_DIR, "status.json")
CANDIDATES_PATH = ENV["CANDIDATES_PATH"] || File.join(Paths::DATA_DIR, "discovered_accounts.json")
SKIPPED_PATH    = ENV["SKIPPED_PATH"] || File.join(Paths::DATA_DIR, "skipped_noncz.json")
# Cache selhaných lookupů (acct → datum) — mrtvé/nekompatibilní instance, smazané
# účty… nezkoušet každý běh. Expirují po FAILED_TTL_DAYS (pak se zkusí znovu).
LOOKUP_FAILED_PATH = ENV["LOOKUP_FAILED_PATH"] || File.join(Paths::DATA_DIR, "lookup_failed.json")
FAILED_TTL_DAYS    = (ENV["FAILED_TTL_DAYS"] || "30").to_i
# Snapshot metrik z minulého běhu → týdenní přírůstky (Skokani v Účtech).
SNAPSHOT_PATH   = ENV["SNAPSHOT_PATH"] || File.join(Paths::DATA_DIR, "metrics_snapshot.json")
# manual_accounts.txt / blocklist.txt se načítají přes CatalogConfig.read_list
# (env override MANUAL_FILE / BLOCKLIST_FILE, jinak ze složky config/).
STATUSES_LIMIT  = (ENV["STATUSES_LIMIT"] || "20").to_i
LIMIT_NEW       = (ENV["LIMIT_NEW"] || "0").to_i
AI_DELAY        = (ENV["AI_DELAY"] || "0.5").to_f
ACTIVE_DAYS     = (ENV["ACTIVE_DAYS"] || "90").to_i  # aktivní = poslední příspěvek ≤ N dní
# Kadence refreshe podle aktivity účtu. Tři čtvrtiny katalogu tvoří účty, které
# nikdy nic nenapsaly nebo mlčí přes rok — obnovovat jim followers každý týden
# je zbytečné (za týden se nezmění) a stojí to většinu času celého běhu.
# Interval 0 = každý běh. Rozhoduje `last_verified_at` z minulého úspěšného
# refreshe; záznam bez něj se obnoví vždy.
DORMANT_DAYS     = (ENV["DORMANT_DAYS"] || "365").to_i        # hranice „mlčí dlouho"
REFRESH_DORMANT  = (ENV["REFRESH_DORMANT_DAYS"] || "28").to_i # 90–365 dní → ~měsíčně
REFRESH_SILENT   = (ENV["REFRESH_SILENT_DAYS"] || "91").to_i  # >365 dní / nikdy → ~čtvrtletně
REFRESH_ALL      = ARGV.include?("--refresh-all") || ENV["REFRESH_ALL"] == "1"
FLUSH_EVERY     = (ENV["FLUSH_EVERY"] || "25").to_i  # lokální checkpoint po N účtech
UPLOAD_EVERY    = (ENV["UPLOAD_EVERY"] || "250").to_i # průběžný upload na Surfer po N účtech (0 = jen na konci)

def log(msg)
  puts "#{Time.now.strftime('%H:%M:%S')} #{msg}"
  $stdout.flush
end

API = MastodonAPI.new(logger: method(:log))
AICLIENT = AI.new(logger: method(:log))

# CZ/SK filtr (běží PŘED placeným AI voláním): instance .cz/.sk nebo z
# instances.txt → ber; jinak jazyk postů cs/sk → ber; jinak výrazná česká/
# slovenská diakritika → ber; jinak přeskoč (lookup+statusy jsou zdarma).
# Vypnutí: --no-czsk-filter.
CZSK_INSTANCES = CatalogConfig.read_list("instances.txt", env_key: "INSTANCES_FILE").to_set
NO_CZSK_FILTER = ARGV.include?("--no-czsk-filter")
CZSK_DIACRITICS = /[ěščřžůňťďľĺŕ]/i
STATS = Hash.new(0)

def looks_czsk?(instance, acct, statuses)
  return true if instance.to_s.end_with?(".cz", ".sk") || CZSK_INSTANCES.include?(instance)
  return true if %w[cs sk].include?(MastodonAPI.dominant_language(statuses))

  text = MastodonAPI.strip_html(acct["note"].to_s + " " + statuses.map { |s| s["content"] }.join(" "))
  text.scan(CZSK_DIACRITICS).size >= 3
end

# Proč se odpověď modelu nepodařilo přečíst. Useknutí na stropu max_tokens
# vypadá v logu stejně jako rozbitý JSON, ale řeší se jinak (zvednout strop,
# ne ladit prompt) — tak ať je to v logu vidět.
def ai_failure_reason(res)
  return "odpověď useknuta (max_tokens=#{AI::MAX_TOKENS})" if res[:stop_reason] == "max_tokens"

  "parse_error"
end

# Vytvoří plný katalogový záznam z kandidáta (lookup + statusy + AI).
# force: true = ruční zařazení (manual_accounts.txt) → obejde CZ/SK filtr
# a nastaví bot: true (typicky boty, které chceme v katalogu napevno).
def categorize_candidate(cand, force: false)
  username = cand["username"]
  instance = cand["instance"]
  acct_full = "#{username}@#{instance}"

  acct = API.lookup(instance, username)
  unless acct
    log("  ❌ @#{acct_full}: lookup selhal")
    return :lookup_failed   # cachovatelné selhání (mrtvá/nekompatibilní instance, smazaný účet)
  end

  # Bota nezařazujeme (autoritativní příznak z přímého lookupu) — pokud nejde
  # o ruční vynucení (manual_accounts.txt). Discovery boty občas propustí, když
  # je federovaný příznak na seed instanci zastaralý; tady je chytíme spolehlivě.
  if acct["bot"] && !force
    STATS[:skipped_bot] += 1
    log("  🤖 @#{acct_full}: přeskočeno (bot)")
    return :skipped_bot
  end

  statuses = API.statuses(instance, acct["id"], limit: STATUSES_LIMIT, exclude_replies: true)
  dom = MastodonAPI.dominant_language(statuses)
  unless force || NO_CZSK_FILTER || looks_czsk?(instance, acct, statuses)
    STATS[:skipped_noncz] += 1
    log("  ⏭  @#{acct_full}: přeskočeno (ne CZ/SK, lang=#{dom.to_s.empty? ? '?' : dom})")
    return :skipped_noncz
  end

  res = AICLIENT.call(AICLIENT.build_prompt(acct, statuses))
  return (log("  ❌ @#{acct_full}: AI #{res[:error]}") && nil) if res[:error]

  parsed = AICLIENT.parse_json(res[:text])
  return (log("  ❌ @#{acct_full}: #{ai_failure_reason(res)}") && nil) unless parsed

  norm = AICLIENT.normalize(parsed, res)
  fam = AICLIENT.map_family(norm["family"])
  cache_note = res[:cache_read_tokens].to_i.positive? ? " 💾" : ""
  log("  #{force ? '➕' : '✅'} @#{acct_full} → #{fam} [#{norm['tags'].join(', ')}]#{cache_note}")

  {
    "id" => acct_full,
    "mastodon_id" => acct["id"],
    "display_name" => (acct["display_name"].to_s.empty? ? username : acct["display_name"]),
    "type" => norm["type"],
    "family" => fam,
    "language" => (dom && !dom.empty? ? dom : "cs"),
    "categories" => norm["tags"],
    "avatar" => acct["avatar"],
    "bio" => acct["note"].to_s,
    "followers" => acct["followers_count"] || 0,
    # null = zatím neměřeno (nový účet bez předchozího snapshotu) → frontend zobrazí „—".
    # Reálné číslo (vč. skutečné 0) doplní refresh_record při dalším běhu.
    "posts_week" => nil,
    "created_at" => (acct["created_at"] ? acct["created_at"][0, 10] : nil),
    "last_status_at" => (acct["last_status_at"] ? acct["last_status_at"][0, 10] : nil),
    "profile_url" => "https://#{instance}/@#{username}",
    "source_platforms" => ["mastodon"],
    "source_details" => [{ "platform" => "mastodon", "handle" => acct_full,
                           "url" => "https://#{instance}/@#{username}" }],
    # bot dle reálného API flagu účtu (ne podle toho, že jde o ruční zařazení) —
    # ruční seznam slouží i pro lidi mimo CZ/SK filtr, ne jen pro boty.
    "bot" => (acct["bot"] ? true : false),
    "_ai_description" => norm["description"],
  }
end

# Cílová adresa migrace z pole `moved` (Mastodon příznak přesunu účtu).
# Vrací "username@instance" nové identity, nebo nil.
def moved_target(acct)
  m = acct["moved"]
  return nil unless m.is_a?(Hash)

  newacct = m["acct"].to_s
  unless newacct.include?("@")
    # fallback z URL: https://instance/@username
    mu = m["url"].to_s.match(%r{https?://([^/]+)/@([^/?#]+)})
    newacct = "#{mu[2]}@#{mu[1]}" if mu
  end
  newacct.include?("@") ? newacct.downcase : nil
end

# Refresh metrik stávajícího záznamu BEZ AI (jen lookup).
def refresh_record(rec, snapshot = nil)
  id = rec["id"].to_s
  return rec unless id.include?("@") # boty bez @ neřešíme

  username, instance = id.split("@", 2)
  acct = API.lookup(instance, username)

  # Selhaný lookup neznamená, že se účet nezměnil — znamená, že o něm nic nevíme.
  # Bez značky by zaniklý účet držel followers i last_status_at z posledního
  # úspěšného běhu donekonečna a tvářil se jako čerstvé číslo. Zaznamenáme tedy,
  # od kdy a kolikrát se ověření nepovedlo; hodnoty samotné necháme být.
  unless acct
    rec = rec.dup
    rec["verify_failures"] = rec["verify_failures"].to_i + 1
    rec["unverified_since"] ||= Date.today.to_s
    STATS[:unverified] += 1
    return rec
  end

  rec = rec.dup
  rec["last_verified_at"] = Date.today.to_s
  rec.delete("verify_failures")
  rec.delete("unverified_since")

  # Migrace účtu: starý profil vrací `moved` → přesměruj záznam na novou adresu.
  # Kurátorovaná metadata (family/type/tagy/categories) zůstávají; metriky vezmeme
  # z čerstvého lookupu nové identity. Když ji nelze ověřit, necháme záznam beze změny.
  newacct = moved_target(acct)
  if newacct && newacct != id
    nu, ninst = newacct.split("@", 2)
    fresh = API.lookup(ninst, nu)
    if fresh
      log("  ↪ migrace #{id} → #{newacct}")
      rec["id"] = newacct
      rec["mastodon_id"] = fresh["id"]
      id = newacct                 # snapshot/delta dál pod novou identitou
      username = nu; instance = ninst
      acct = fresh                 # další pole refreshuj z nové identity
    else
      log("  ⚠️  #{id} se přesunul na #{newacct}, ale nelze ověřit — ponecháno")
    end
  end

  rec["followers"] = acct["followers_count"] if acct["followers_count"]
  rec["avatar"] = acct["avatar"] if acct["avatar"]
  rec["bio"] = acct["note"].to_s if acct["note"]
  rec["mastodon_id"] ||= acct["id"]
  # Aktivita pro frontend filtr „jen aktivní" — obnovuje se každý běh.
  rec["last_status_at"] = acct["last_status_at"][0, 10] if acct["last_status_at"]
  # Skutečný bot příznak (autoritativní) — umožní vyřadit boty, co propustila discovery.
  rec["bot"] = acct["bot"] ? true : false

  # Týdenní přírůstky (Skokani v Účtech) + příspěvků/týden — rozdíl proti snapshotu
  # z minulého běhu.
  if snapshot
    cur_f = acct["followers_count"]
    cur_s = acct["statuses_count"]
    now   = Time.now.utc
    prev  = snapshot[id]
    rec["followers_delta"] = cur_f - prev["followers"] if prev && cur_f && prev["followers"]
    if prev && cur_s && prev["statuses"]
      delta = cur_s - prev["statuses"]
      rec["activity_delta"] = delta
      # posts_week = přírůstek příspěvků normalizovaný na 7 dní (zvládne i
      # nepravidelné/ruční běhy). Záporný přírůstek (smazané posty) → 0.
      # Bez prev["at"] (starý snapshot) předpokládáme týdenní kadenci.
      days = prev["at"] ? ((now - Time.parse(prev["at"])) / 86_400.0) : 7.0
      if days >= 0.5
        rate = (delta / days) * 7.0
        rec["posts_week"] = rate.negative? ? 0 : rate.round
      end
      # days < 0.5 (dva běhy hned po sobě) → ponech stávající posts_week.
    else
      # Chybí baseline (nový účet / první měření) → zatím neměřeno → „—".
      rec["posts_week"] = nil
    end
    snapshot[id] = { "followers" => cur_f, "statuses" => cur_s, "at" => now.iso8601 } if cur_f || cur_s
  end
  rec
end

# Počet dní od posledního příspěvku, nebo nil (účet nikdy nic nepublikoval —
# chybějící last_status_at je u Mastodonu právě tohle, ne chyba sběru).
def days_since_post(rec)
  d = rec["last_status_at"].to_s
  return nil if d.empty?

  (Date.today - Date.parse(d)).to_i
rescue ArgumentError
  nil
end

# Aktivní účet = poslední příspěvek do ACTIVE_DAYS dní (shodné s frontendem).
def active?(rec)
  d = days_since_post(rec)
  !d.nil? && d <= ACTIVE_DAYS
end

# Jak často účet obnovovat: :active každý běh, :dormant ~měsíčně, :silent ~čtvrtletně.
def refresh_tier(rec)
  d = days_since_post(rec)
  return :silent if d.nil?          # nikdy nepublikoval
  return :active if d <= ACTIVE_DAYS
  return :dormant if d <= DORMANT_DAYS

  :silent
end

# Má se účet v tomhle běhu obnovovat? Účet bez `last_verified_at` (nový nebo
# z doby před zavedením značky) se obnoví vždy.
def due_for_refresh?(rec)
  return true if REFRESH_ALL

  interval = case refresh_tier(rec)
             when :active then 0
             when :dormant then REFRESH_DORMANT
             else REFRESH_SILENT
             end
  return true if interval.zero?

  seen = rec["last_verified_at"].to_s
  return true if seen.empty?

  (Date.today - Date.parse(seen)).to_i >= interval
rescue ArgumentError
  true
end

# Lehká klasifikace TYPU z uloženého bia + jména (bez stahování postů → levné).
# Vrací jeden z AI::VALID_TYPES, nebo nil při chybě.
def classify_type(rec)
  acct = { "note" => rec["bio"].to_s, "display_name" => rec["display_name"].to_s, "fields" => [] }
  res = AICLIENT.call(AICLIENT.build_prompt(acct, []))
  return nil if res[:error]

  parsed = AICLIENT.parse_json(res[:text])
  parsed && AICLIENT.normalize(parsed, res)["type"]
end

# Přeznačení rodiny u už katalogizovaného účtu. Na rozdíl od typu (bio stačí)
# se rodina řídí PŘEVAŽUJÍCÍM TÉMATEM účtu, takže potřebuje i posty — proto plný
# lookup + statusy + AI, stejně jako u nového účtu. Vrací [family, tags] / nil.
def classify_family(rec)
  username, instance = rec["id"].to_s.split("@", 2)
  return nil unless username && instance

  acct = API.lookup(instance, username)
  return nil unless acct

  statuses = API.statuses(instance, acct["id"], limit: STATUSES_LIMIT, exclude_replies: true)
  res = AICLIENT.call(AICLIENT.build_prompt(acct, statuses))
  return nil if res[:error]

  parsed = AICLIENT.parse_json(res[:text])
  return (log("  ❌ @#{rec['id']}: #{ai_failure_reason(res)}") && nil) unless parsed

  norm = AICLIENT.normalize(parsed, res)
  [AICLIENT.map_family(norm["family"]), norm["tags"]]
end

# Dedup katalogu podle id, case-insensitive (Mastodon handle je nezávislý na
# velikosti písmen). Řeší jak migrace (`moved` → starý záznam ukazuje na adresu,
# která už v katalogu je), tak duplicity lišící se jen velikostí písmen.
# Ze skupiny zůstane záznam s NEJNOVĚJŠÍ aktivitou (`last_status_at`), při shodě
# ten dřívější v pořadí (kurátorovaný) — nikdy tedy nepřebije živý záznam mrtvým.
def dedup_by_id(records)
  fresh = ->(rec) { (rec["last_status_at"] || "").to_s }
  best = {}
  records.each_with_index do |r, i|
    key = r["id"].to_s.downcase
    cur = best[key]
    best[key] = i if cur.nil? || fresh.call(r) > fresh.call(records[cur])
  end
  keep = best.values.to_set
  records.each_with_index.select { |_r, i| keep.include?(i) }.map(&:first)
end

# Účty, na které cílí --refamily: aktivní a sedící v některé z REFAMILY_FROM rodin.
def refamily_targets(catalog)
  catalog.select { |r| r["id"].to_s.include?("@") && active?(r) && REFAMILY_FROM.include?(r["family"]) }
end

# Odhad rozsahu a ceny --retype (jen výpis, nic nemění). Samotné přetypování
# probíhá v rámci běžného průchodu v main() — tady by mělo vlastní, druhou kopii
# zápisu i uploadu, což se rozešlo hned, jak katalog dostal oddělené úložiště.
def estimate_retype(catalog)
  targets = catalog.select { |r| r["id"].to_s.include?("@") && active?(r) }
  log("RETYPE: aktivních účtů k přeznačení typu: #{targets.size} / #{catalog.size}")
  log("Odhad ceny (bio-only, ~$0.004/účet): ~$#{format('%.2f', targets.size * 0.004)} — nic nemění.")
end

def main
  # Migrace ze starého uspořádání (jediný soubor web/data.json): když úložiště
  # ještě neexistuje, načteme katalog z publikované verze a od téhle chvíle se
  # zapisuje do obou.
  source = File.exist?(CATALOG_PATH) ? CATALOG_PATH : PUBLIC_PATH
  abort("❌ Katalog nenalezen: #{CATALOG_PATH} ani #{PUBLIC_PATH}") unless File.exist?(source)
  log("ℹ️  Úložiště #{CATALOG_PATH} zatím neexistuje → přebírám katalog z #{PUBLIC_PATH}") if source != CATALOG_PATH
  abort("❌ Kandidáti nenalezeni: #{CANDIDATES_PATH}") unless RETYPE || REFAMILY || File.exist?(CANDIDATES_PATH)

  catalog = JSON.parse(File.read(source, encoding: "UTF-8"))
  catalog = catalog.is_a?(Array) ? catalog : []

  # --retype --dry-run: jen odhad ceny přetypování (nic nemění). Reálný --retype
  # se provede v rámci běžného průchodu (refresh+moved → přetypování → zápis).
  if RETYPE && DRY_RUN
    estimate_retype(catalog)
    return
  end

  # --refamily --dry-run: kolik účtů by se přeznačilo a za kolik (nic nemění).
  if REFAMILY && DRY_RUN
    targets = refamily_targets(catalog)
    log("REFAMILY: aktivních účtů v rodinách #{REFAMILY_FROM.join('/')}: #{targets.size} / #{catalog.size}")
    log("Odhad ceny (plná klasifikace vč. postů, ~$0.0079/účet): " \
        "~$#{format('%.2f', targets.size * 0.0079)} — nic nemění.")
    return
  end

  candidates = File.exist?(CANDIDATES_PATH) ? JSON.parse(File.read(CANDIDATES_PATH, encoding: "UTF-8")) : []
  candidates = candidates.is_a?(Array) ? candidates : []

  # Blocklist (blocklist.txt) — handle, které se VŽDY vyřadí: odstraní z katalogu
  # a nikdy znovu nepřidají (řeší i žádosti vlastníků o odstranění z patičky webu).
  blocklist = CatalogConfig.read_handle_set("blocklist.txt", env_key: "BLOCKLIST_FILE")
  if blocklist.any?
    before = catalog.size
    catalog = catalog.reject { |r| blocklist.include?(r["id"].to_s.downcase) }
    removed = before - catalog.size
    log("Blocklist: #{blocklist.size} účtů | odebráno z katalogu: #{removed}") if removed.positive? || DRY_RUN
  end

  # Mrtvé/zaniklé instance (dead_instances.txt) — doménová úroveň. Účty z nich
  # vyřadíme z katalogu a nebereme jako kandidáty: federovaný graf je drží jako
  # „duchy" (např. mastodon.arch-linux.cz: 1500+), lookup na ně jen timeoutuje.
  dead_instances = CatalogConfig.read_list("dead_instances.txt", env_key: "DEAD_INSTANCES_FILE")
                                .map(&:downcase).to_set
  if dead_instances.any?
    before = catalog.size
    catalog = catalog.reject { |r| dead_instances.include?(r["id"].to_s.split("@").last.to_s.downcase) }
    removed = before - catalog.size
    log("Mrtvé instance: #{dead_instances.size} domén | odebráno z katalogu: #{removed}") if removed.positive? || DRY_RUN
  end

  # Cache dříve přeskočených ne-CZ/SK účtů → nedotazovat je znovu.
  skipped_set = if RECHECK_SKIPPED || !File.exist?(SKIPPED_PATH)
                  Set.new
                else
                  Set.new(Array(JSON.parse(File.read(SKIPPED_PATH, encoding: "UTF-8"))))
                end

  # Cache selhaných lookupů (acct → datum). Účty starší než FAILED_TTL_DAYS se
  # „odpustí" (zkusí znovu — instance se mohla vrátit). RECHECK_SKIPPED resetuje.
  failed_map = if RECHECK_SKIPPED || !File.exist?(LOOKUP_FAILED_PATH)
                 {}
               else
                 (JSON.parse(File.read(LOOKUP_FAILED_PATH, encoding: "UTF-8")) rescue {})
               end
  failed_map = {} unless failed_map.is_a?(Hash)
  failed_cutoff = Date.today - FAILED_TTL_DAYS
  failed_map.select! { |_a, d| (Date.parse(d.to_s) rescue Date.new(1970)) >= failed_cutoff }
  failed_set = failed_map.keys.to_set

  # Pozn.: Mastodon handle je case-insensitive (@OttoVonWenkoff == @ottovonwenkoff),
  # proto porovnáváme přes downcase, ať nevzniknou duplicity lišící se velikostí písmen.
  existing_ids = catalog.map { |r| r["id"].to_s.downcase }.to_set
  new_cands = candidates.reject do |c|
    existing_ids.include?(c["acct"].to_s.downcase) || skipped_set.include?(c["acct"]) ||
      blocklist.include?(c["acct"].to_s.downcase) || dead_instances.include?(c["instance"].to_s.downcase) ||
      failed_set.include?(c["acct"]) || MastodonAPI.bridge?(c["instance"])
  end
  new_cands = new_cands.first(LIMIT_NEW) if LIMIT_NEW.positive?

  # Ruční zařazení (manual_accounts.txt) — vynucené: obejde CZ/SK filtr i vyřazení
  # botů, označí bot: true. manual_new = ty, co ještě v katalogu nejsou. Blocklist
  # má přednost (kdyby byl handle omylem v obou).
  manual_handles = CatalogConfig.read_list("manual_accounts.txt", env_key: "MANUAL_FILE")
                                .reject { |h| blocklist.include?(h.downcase) }
  manual_set = manual_handles.map(&:downcase).to_set
  manual_new = manual_handles.reject { |h| existing_ids.include?(h.to_s.downcase) }

  log("Katalog: #{catalog.size} účtů | kandidátů: #{candidates.size} | " \
      "přeskočených (cache): #{skipped_set.size} | NOVÝCH ke zpracování: #{new_cands.size} | " \
      "ruční (nové): #{manual_new.size}")
  log("Režim: dry-run=#{DRY_RUN} categorize=#{!NO_CATEGORIZE} refresh=#{!NO_REFRESH} upload=#{!NO_UPLOAD}")

  if DRY_RUN
    log("")
    log("=== DRY-RUN: nové účty, které by se kategorizovaly ===")
    new_cands.first(50).each { |c| log("  + #{c['acct']} (#{c['followers_count']} foll.)") }
    log("  … a další #{new_cands.size - 50}") if new_cands.size > 50
    if manual_new.any?
      log("")
      log("=== DRY-RUN: ruční účty (manual_accounts.txt) — vynuceně, bot: true ===")
      manual_new.each { |h| log("  ➕ #{h}") }
    end
    log("")
    log("Odhad ceny (HORNÍ MEZ, bez CZ/SK filtru) #{new_cands.size + manual_new.size} účtů: " \
        "~$#{format('%.2f', (new_cands.size + manual_new.size) * 0.0079)}")
    unless NO_CZSK_FILTER
      log("ℹ️  CZ/SK filtr běží až za běhu (potřebuje statusy) → reálně se zaplatí jen")
      log("    účty na .cz/.sk instanci, nebo s posty cs/sk, nebo s českou diakritikou.")
      log("    Skutečná cena bude NIŽŠÍ. Tip: ověř LIMIT_NEW=50 a sleduj poměr přeskočených.")
    end
    return
  end

  # 1) Refresh stávajících (bez AI)
  refreshed = catalog
  snapshot = (JSON.parse(File.read(SNAPSHOT_PATH, encoding: "UTF-8")) rescue {})
  snapshot = {} unless snapshot.is_a?(Hash)
  unless NO_REFRESH
    log("")
    log("── Refresh metrik stávajících (bez AI) ──")
    # Obnovujeme každý účet s handle (@) — osoby i ruční boty (last_status_at,
    # followers…), aby filtr „jen aktivní" fungoval i na botech.
    refreshable = catalog.count { |r| r["id"].to_s.include?("@") }
    done = 0
    deltas = 0
    postponed = Hash.new(0)
    refreshed = catalog.map do |rec|
      next rec unless rec["id"].to_s.include?("@")

      # Odložené účty (mlčící / nikdy nepublikující) tenhle běh přeskočíme —
      # viz DORMANT/SILENT výše. posts_week si s nepravidelnou kadencí poradí,
      # přírůstek se normalizuje na 7 dní podle `at` ve snapshotu.
      unless due_for_refresh?(rec)
        postponed[refresh_tier(rec)] += 1
        next rec
      end

      done += 1
      r = refresh_record(rec, snapshot)
      deltas += 1 if r["followers_delta"] || r["activity_delta"]
      log("  ↻ #{rec['id']} followers=#{r['followers']}") if (done % 25).zero?
      r
    end
    log("  Obnoveno #{done}/#{refreshable} účtů (přírůstky u #{deltas})")
    if postponed.any?
      log("  ⏭  Odloženo dle kadence: mlčící #{postponed[:dormant]} (á #{REFRESH_DORMANT} dní), " \
          "dlouho mlčící/bez postů #{postponed[:silent]} (á #{REFRESH_SILENT} dní) — vynutit: --refresh-all")
    end
    if STATS[:unverified].positive?
      stale = refreshed.select { |r| r["unverified_since"] }
      oldest = stale.map { |r| r["unverified_since"] }.min
      log("  ⚠️  Neověřeno (lookup selhal): #{STATS[:unverified]} účtů | " \
          "celkem s neověřenými daty: #{stale.size}, nejstarší od #{oldest}")
    end

    # Vyřaď boty (skutečný příznak z refreshe), které nejsou ručně povolené.
    before_bots = refreshed.size
    refreshed = refreshed.reject { |r| r["bot"] && !manual_set.include?(r["id"].to_s.downcase) }
    dropped = before_bots - refreshed.size
    log("  🤖 Odebráno botů (mimo manual_accounts.txt): #{dropped}") if dropped.positive?
  end

  # Záloha původního katalogu JEDNOU (před prvním zápisem), pak checkpointy.
  backup = "#{CATALOG_PATH}.bak"
  File.write(backup, File.read(source)) if File.exist?(source)

  # Atomický zápis (temp + rename) — crash nezanechá rozbitý JSON.
  write_json = lambda do |path, data|
    tmp = "#{path}.tmp"
    File.write(tmp, JSON.pretty_generate(data))
    File.rename(tmp, path)
  end

  # Zapiš úložiště i publikovanou verzi najednou (checkpointy i finální zápis),
  # ať jsou průběžné uploady konzistentní. Slim payload řeší Catalog.publish.
  save_both = lambda do |data|
    write_json.call(CATALOG_PATH, data)
    Catalog.publish(data, PUBLIC_PATH)
  end

  # 1b) Přetypování aktivních (--retype) — type-only AI (bio+jméno), levné. Mutuje
  # `refreshed` rovnou (cíle jsou tytéž objekty), s průběžnými checkpointy/uploadem.
  if RETYPE
    if AICLIENT.instance_variable_get(:@api_key).to_s.empty?
      abort("❌ Chybí ANTHROPIC_API_KEY (nutné pro --retype)")
    end
    targets = refreshed.select { |r| r["id"].to_s.include?("@") && active?(r) }
    log("")
    log("── Přetypování aktivních (--retype): #{targets.size} účtů ──")
    rch = 0
    last_up = 0
    targets.each_with_index do |rec, i|
      tp = classify_type(rec)
      if tp && tp != rec["type"]
        log("  ✏️  #{rec['id']}: #{rec['type']} → #{tp}")
        rec["type"] = tp
        rch += 1
      end
      sleep(AI_DELAY) if AI_DELAY.positive?

      next unless FLUSH_EVERY.positive? && ((i + 1) % FLUSH_EVERY).zero?

      save_both.call(refreshed)
      log("  💾 checkpoint @#{i + 1}/#{targets.size}: typů #{rch}")
      if !NO_UPLOAD && UPLOAD_EVERY.positive? && (i + 1 - last_up) >= UPLOAD_EVERY
        Surfer.upload(PUBLIC_PATH, logger: method(:log))
        last_up = i + 1
      end
    end
    log("  Přetypováno: #{rch}/#{targets.size}")
  end

  # 1c) Přeznačení rodiny (--refamily) — cílí na koš `lifestyle`. Plná klasifikace
  # (lookup + posty + AI), takže se počítá jako nový účet; proto jen AKTIVNÍ účty
  # v REFAMILY_FROM, ne celý katalog. Stejné checkpointy/upload jako u --retype.
  if REFAMILY
    if AICLIENT.instance_variable_get(:@api_key).to_s.empty?
      abort("❌ Chybí ANTHROPIC_API_KEY (nutné pro --refamily)")
    end
    targets = refamily_targets(refreshed)
    log("")
    log("── Přeznačení rodiny (--refamily) z #{REFAMILY_FROM.join('/')}: #{targets.size} účtů ──")
    fch = 0
    last_up = 0
    targets.each_with_index do |rec, i|
      fam, tags = classify_family(rec)
      if fam && fam != rec["family"]
        log("  🏷  #{rec['id']}: #{rec['family']} → #{fam}")
        rec["family"] = fam
        rec["categories"] = tags if tags && tags.any?
        fch += 1
      end
      sleep(AI_DELAY) if AI_DELAY.positive?

      next unless FLUSH_EVERY.positive? && ((i + 1) % FLUSH_EVERY).zero?

      save_both.call(refreshed)
      log("  💾 checkpoint @#{i + 1}/#{targets.size}: rodin #{fch}")
      if !NO_UPLOAD && UPLOAD_EVERY.positive? && (i + 1 - last_up) >= UPLOAD_EVERY
        Surfer.upload(PUBLIC_PATH, logger: method(:log))
        last_up = i + 1
      end
    end
    log("  Přeznačeno rodin: #{fch}/#{targets.size}")
  end

  # 2) Kategorizace nových (AI) — s průběžnými checkpointy (crash-safe, resumable)
  added = []
  if NO_CATEGORIZE
    log("")
    write_json.call(File.join(Paths::DATA_DIR, "new_candidates.json"), new_cands)
    log("⏭  --no-categorize → zapsáno new_candidates.json (#{new_cands.size}); nekategorizováno.")
  elsif new_cands.any?
    if AICLIENT.instance_variable_get(:@api_key).to_s.empty?
      abort("❌ Chybí ANTHROPIC_API_KEY (nutné pro kategorizaci nových účtů)")
    end
    log("")
    log("── Kategorizace #{new_cands.size} nových účtů (AI) ──")

    checkpoint = lambda do
      write_json.call(SKIPPED_PATH, skipped_set.to_a.sort)
      write_json.call(LOOKUP_FAILED_PATH, failed_map)
      save_both.call(refreshed + added)
    end

    last_upload_at = 0
    new_cands.each_with_index do |c, i|
      rec = categorize_candidate(c)
      case rec
      when :skipped_noncz, :skipped_bot then skipped_set << c["acct"]  # ne-CZ/SK / bot → cache
      when :lookup_failed then failed_map[c["acct"]] = Date.today.to_s # selhal lookup → cache (s expirací)
      when Hash then added << rec
      end
      sleep(AI_DELAY) if AI_DELAY.positive?

      next unless FLUSH_EVERY.positive? && ((i + 1) % FLUSH_EVERY).zero?

      checkpoint.call
      log("  💾 checkpoint @#{i + 1}/#{new_cands.size}: katalog +#{added.size}, " \
          "cache #{skipped_set.size}")

      # Průběžný (throttlovaný) upload na Surfer — data.json je čerstvě zapsaný výše.
      if !NO_UPLOAD && UPLOAD_EVERY.positive? && (i + 1 - last_upload_at) >= UPLOAD_EVERY
        Surfer.upload(PUBLIC_PATH, logger: method(:log))
        last_upload_at = i + 1
      end
    end
    checkpoint.call # finální flush
    saved = STATS[:skipped_noncz] + STATS[:skipped_bot]
    log("  Kategorizováno (zaplaceno): #{added.size} | ne-CZ/SK: #{STATS[:skipped_noncz]} | " \
        "boti: #{STATS[:skipped_bot]} | úspora ~$#{format('%.2f', saved * 0.0079)}")
  end

  # 2b) Ruční účty (manual_accounts.txt) — vynucené zařazení (obejde CZ/SK filtr
  # i vyřazení botů). bot příznak se bere z REÁLNÉHO API flagu (viz categorize_candidate),
  # ne vynuceně — lidé tu mají bot:false, skuteční boti bot:true.
  manual_added = []
  if !NO_CATEGORIZE && manual_new.any?
    if AICLIENT.instance_variable_get(:@api_key).to_s.empty?
      abort("❌ Chybí ANTHROPIC_API_KEY (nutné i pro ruční účty)")
    end
    log("")
    log("── Ruční účty (#{manual_new.size}, vynucené zařazení, bot dle reality) ──")
    manual_new.each do |h|
      u, inst = h.split("@", 2)
      next log("  ⚠️  špatný formát handle: #{h}") unless u && inst

      rec = categorize_candidate({ "username" => u, "instance" => inst, "acct" => h }, force: true)
      manual_added << rec if rec.is_a?(Hash)
      sleep(AI_DELAY) if AI_DELAY.positive?
    end
  end

  # 3) Sloučení + zápis (i pro případ NO_CATEGORIZE / refresh-only)
  result = refreshed + added + manual_added
  # Dedup podle id (case-insensitive — handle je u Mastodonu nezávislý na velikosti
  # písmen). Řeší jak migrace (moved → starý záznam přesměrován na existující adresu),
  # tak duplicity lišící se jen velikostí písmen. Z každé skupiny necháme záznam
  # s NEJNOVĚJŠÍ aktivitou (last_status_at), při shodě ten dřívější v katalogu
  # (kurátorovaný) — tím nikdy nepreferujeme „mrtvý"/neobnovený záznam před živým.
  before_uniq = result.size
  result = dedup_by_id(result)
  dups = before_uniq - result.size
  log("Dedup (case-insensitive): sloučeno #{dups} duplicit") if dups.positive?
  # Pozn.: ruční účty (manual_accounts.txt) si bot příznak drží z reálného API
  # flagu (viz categorize_candidate / refresh_record) — žádné vynucování bot:true,
  # ať lidé přidaní ručně (mimo CZ/SK filtr) nedostanou badge „Automat".
  save_both.call(result)
  # Cache selhaných lookupů (vč. prořezání expirovaných) — i pro refresh-only běh.
  write_json.call(LOOKUP_FAILED_PATH, failed_map)
  # Snapshot metrik pro příští výpočet týdenních přírůstků (jen po refreshi).
  write_json.call(SNAPSHOT_PATH, snapshot) unless NO_REFRESH
  log("")
  log("✅ Hotovo. Katalog: #{catalog.size} → #{result.size} " \
      "(nově #{added.size}, ruční #{manual_added.size}). Záloha: #{backup}")

  # Datum aktualizace katalogu → status.json (patička webu). Merge, ať nepřepíšeme
  # search_indexed od build-search.
  status = (JSON.parse(File.read(STATUS_PATH, encoding: "UTF-8")) rescue {})
  status = {} unless status.is_a?(Hash)
  status["catalog_updated"] = Time.now.utc.iso8601
  # Práh aktivity publikujeme, ať ho frontend nemá zvlášť natvrdo — jinak by změna
  # ACTIVE_DAYS tiše rozjela filtr „jen aktivní" na webu a hranici uvedenou v FAQ.
  status["active_days"] = ACTIVE_DAYS
  write_json.call(STATUS_PATH, status)

  # 4) Upload na Surfer
  if NO_UPLOAD
    log("⏭  --no-upload → data.json + status.json zůstávají jen lokálně.")
  else
    Surfer.upload(PUBLIC_PATH, logger: method(:log))
    Surfer.upload(STATUS_PATH, logger: method(:log))
  end
end

main if __FILE__ == $PROGRAM_NAME
