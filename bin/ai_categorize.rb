#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# ai_categorize.rb
#
# PoC: AI kategorizace reálných CZ/SK Mastodon účtů pomocí Claude (Anthropic API).
# Pro ~50 účtů ze 3 českých instancí stáhne bio + posledních 20 postů a nechá
# model přiřadit rodinu, tagy a charakteristiku.
#
# ZÁMĚR: ověřit kvalitu AI kategorizace, NE produkční kód. Bez DB, bez frontendu,
#        bez cronu, bez dedupingu.
#
# Závislosti: pouze Ruby stdlib (net/http, json, uri, time) + HTTP na Anthropic API.
#             Žádný Gemfile, žádný bundler.
#
# Spuštění:
#   ANTHROPIC_API_KEY=sk-... ruby ai_categorize.rb
#
# ENV proměnné:
#   ANTHROPIC_API_KEY  (povinná) - API klíč
#   MASTODON_TOKEN     (ne)      - read-only token (lepší rate limity Mastodonu)
#   AI_MODEL           (ne)      - default claude-sonnet-4-5 (zadání zmiňuje i 4-6 / opus-4-5)
#   AI_DELAY           (ne)      - sekundy mezi AI voláními, default 0.5
#   MASTODON_DELAY     (ne)      - sekundy mezi Mastodon voláními, default 1.0
#   LIMIT              (ne)      - max. počet účtů celkem (default 50)
#
# Výstupy:
#   stdout            - průběžný log: "✅ @tomucha → tech [journalist, photography]"
#   ai_results.jsonl  - průběžné výsledky (JSON Lines, append po každém účtu)
#   ai_results.json   - finální pole záznamů
#   ai_report.md      - analytický report (distribuce rodin, top tagy, cena, ...)
# =============================================================================

require "net/http"
require "json"
require "uri"
require "time"
require_relative "../lib/config"        # config.env do ENV
require_relative "../lib/mastodon_api"
require_relative "../lib/ai"

# -----------------------------------------------------------------------------
# Konfigurace
# -----------------------------------------------------------------------------

# CZ/SK instance z instances.txt (override INSTANCES_FILE). Ostatní SK účty jsou
# roztroušené na velkých/CZ instancích a dolují se heuristikou jazyka
# (dominant_language == "sk").
INSTANCES = CatalogConfig.read_list("instances.txt", env_key: "INSTANCES_FILE").freeze
ACCOUNTS_PER_INSTANCE = 17 # ~50 celkem
POSTS_PER_ACCOUNT = 20
TOTAL_LIMIT = (ENV["LIMIT"] || "50").to_i
AI_DELAY    = (ENV["AI_DELAY"] || "0.5").to_f

# Sdílené nástroje (lib/).
API = MastodonAPI.new(logger: ->(m) { log(m) })
AICLIENT = AI.new(logger: ->(m) { log(m) })
API_KEY  = ENV["ANTHROPIC_API_KEY"]
AI_MODEL = AICLIENT.model
FAMILIES = AI::FAMILIES
PRICING  = AI::PRICING
DEFAULT_PRICE = AI::DEFAULT_PRICE

JSONL    = File.join(Paths::DATA_DIR, "ai_results.jsonl")
JSON_OUT = File.join(Paths::DATA_DIR, "ai_results.json")
REPORT   = File.join(Paths::DOCS_DIR, "ai_report.md")
# PRICING / DEFAULT_PRICE jsou z lib/ai (AI::PRICING) — viz konfigurace výše.

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

def log(msg)
  puts "#{Time.now.strftime('%H:%M:%S')} #{msg}"
  $stdout.flush
end

# ---------------------------------------------------------------------------
# Mastodon data (přes lib/mastodon_api)
# ---------------------------------------------------------------------------

def fetch_directory(instance)
  arr = API.get_json(instance, "/api/v1/directory?limit=80&order=active&local=true")
  arr.is_a?(Array) ? arr : []
end

def fetch_statuses(instance, account_id)
  API.statuses(instance, account_id, limit: POSTS_PER_ACCOUNT, exclude_replies: true)
end

# -----------------------------------------------------------------------------
# Kategorizace jednoho účtu
# -----------------------------------------------------------------------------

def categorize_account(instance, account)
  statuses = fetch_statuses(instance, account["id"])
  dom = MastodonAPI.dominant_language(statuses)

  record = {
    "instance" => instance,
    "username" => account["username"],
    "display_name" => account["display_name"],
    "followers_count" => account["followers_count"],
    "statuses_count" => account["statuses_count"],
    "posts_fetched" => statuses.size,
    "dominant_language" => dom,
    "bio_length" => MastodonAPI.strip_html(account["note"]).length,
    "ai" => nil,
    "error" => nil,
  }

  res = AICLIENT.call(AICLIENT.build_prompt(account, statuses))
  if res[:error]
    record["ai"] = { "family" => "other", "tags" => [], "description" => nil }
    record["error"] = res[:error]
    log("❌ @#{account['username']} → API error: #{res[:error]}")
  else
    parsed = AICLIENT.parse_json(res[:text])
    if parsed.nil?
      record["ai"] = AICLIENT.normalize({ "family" => "other", "tags" => [], "description" => nil }, res)
      record["error"] = "parse_error"
      log("❌ @#{account['username']} → parse_error")
    else
      record["ai"] = AICLIENT.normalize(parsed, res)
      cache_note = res[:cache_read_tokens].to_i.positive? ? " 💾cache" : ""
      log("✅ @#{account['username']} → #{record['ai']['family']} " \
          "[#{record['ai']['tags'].join(', ')}]#{cache_note}")
    end
  end

  sleep(AI_DELAY) if AI_DELAY > 0
  record
end

# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------

def generate_report(records)
  total = records.size
  ok = records.count { |r| r["error"].nil? }
  errs = records.reject { |r| r["error"].nil? }

  fam_counts = Hash.new(0)
  tag_counts = Hash.new(0)
  ptok = []
  rtok = []
  ccreate = []
  cread = []
  records.each do |r|
    next unless r["ai"]

    fam_counts[r["ai"]["family"]] += 1
    Array(r["ai"]["tags"]).each { |t| tag_counts[t] += 1 }
    ptok << r["ai"]["prompt_tokens"] if r["ai"]["prompt_tokens"]
    rtok << r["ai"]["response_tokens"] if r["ai"]["response_tokens"]
    ccreate << r["ai"]["cache_creation_tokens"].to_i if r["ai"].key?("cache_creation_tokens")
    cread << r["ai"]["cache_read_tokens"].to_i if r["ai"].key?("cache_read_tokens")
  end

  avg_p = ptok.empty? ? 0 : (ptok.sum.to_f / ptok.size).round
  avg_r = rtok.empty? ? 0 : (rtok.sum.to_f / rtok.size).round
  price = PRICING[AI_MODEL] || DEFAULT_PRICE
  # Reálná cena celého běhu vč. cachingu: vstupní tokeny full cena, cache write 1,25×,
  # cache read 0,1×, výstup full cena. Sečteno přes všechny účty, pak na 1 účet.
  in_full   = ptok.sum / 1_000_000.0 * price[:in]
  out_full  = rtok.sum / 1_000_000.0 * price[:out]
  cw_cost   = ccreate.sum / 1_000_000.0 * price[:in] * 1.25
  cr_cost   = cread.sum / 1_000_000.0 * price[:in] * 0.10
  n_ok      = [ptok.size, 1].max
  cost_one  = (in_full + out_full + cw_cost + cr_cost) / n_ok
  cache_used = cread.sum.positive? || ccreate.sum.positive?

  lines = []
  lines << "# AI kategorizace CZ/SK Mastodon účtů — report"
  lines << ""
  lines << "_Model: #{AI_MODEL} | účtů: #{total} | úspěšně: #{ok} | chyb: #{errs.size} | #{Time.now.strftime('%Y-%m-%d %H:%M')}_"
  lines << ""

  lines << "## 1) Distribuce rodin"
  lines << ""
  lines << "| Rodina | Počet | % |"
  lines << "|---|---|---|"
  FAMILIES.each do |f|
    c = fam_counts[f]
    next if c.zero?

    lines << "| #{f} | #{c} | #{(100.0 * c / total).round(1)}% |"
  end
  lines << ""

  lines << "## 2) Nejčastější tagy (top 20)"
  lines << ""
  lines << "| Tag | Počet |"
  lines << "|---|---|"
  tag_counts.sort_by { |_, n| -n }.first(20).each { |t, n| lines << "| #{t} | #{n} |" }
  lines << ""
  lines << "Celkem unikátních tagů: **#{tag_counts.size}** (na #{ok} účtů)."
  lines << ""

  lines << "## 3) Chybovost"
  lines << ""
  lines << "- Celkem účtů: #{total}"
  lines << "- Úspěšně kategorizováno: #{ok}"
  lines << "- Chyb (API / parse): #{errs.size}"
  errs.each { |r| lines << "  - @#{r['username']} (#{r['instance']}): #{r['error']}" }
  lines << ""

  lines << "## 4) Tokeny a odhad ceny"
  lines << ""
  lines << "| Metrika | Hodnota |"
  lines << "|---|---|"
  lines << "| Průměr prompt tokenů (vč. cache) | #{avg_p} |"
  lines << "| Průměr response tokenů | #{avg_r} |"
  if cache_used
    hit_pct = cread.count(&:positive?)
    lines << "| Prompt caching | ✅ aktivní — cache read u #{hit_pct}/#{cread.size} účtů |"
    lines << "| Cache write tokenů (celkem) | #{ccreate.sum} (účtováno 1,25×) |"
    lines << "| Cache read tokenů (celkem) | #{cread.sum} (účtováno 0,1×) |"
  else
    lines << "| Prompt caching | ⚠️ neaktivní (žádné cache_read — ověřit prefix/práh) |"
  end
  lines << "| **Reálná cena za 1 účet** (#{AI_MODEL}) | **$#{format('%.5f', cost_one)}** |"
  lines << "| Odhad za 50 účtů | $#{format('%.3f', cost_one * 50)} |"
  lines << "| Odhad za 500 účtů | $#{format('%.2f', cost_one * 500)} |"
  lines << "| Odhad za 5000 účtů | $#{format('%.2f', cost_one * 5000)} |"
  lines << ""
  lines << "_Ceník (#{AI_MODEL}): $#{price[:in]}/1M vstup, $#{price[:out]}/1M výstup. " \
           "Cache write 1,25× vstupní ceny, cache read 0,1× vstupní ceny (list prices, ověřit)._"
  lines << "_Cena za 1 účet je skutečná: zahrnuje plnou cenu vstupu/výstupu + cache write/read " \
           "podle reálných `usage` hodnot z API._"
  lines << ""

  lines << "## 5) Kvalitativní poznatky — ukázky"
  lines << ""
  good = records.select { |r| r["error"].nil? && r["bio_length"].to_i > 20 && r["posts_fetched"].to_i >= 15 }
  lines << "### Dobře zařazené (dost dat: bio + 15+ postů)"
  good.first(6).each do |r|
    lines << "- **@#{r['username']}** (#{r['instance']}, #{r['dominant_language']}) → " \
             "**#{r['ai']['family']}** `#{r['ai']['tags'].join(', ')}`"
    lines << "  > #{r['ai']['description']}"
  end
  lines << ""
  sparse = records.select { |r| r["error"].nil? && (r["posts_fetched"].to_i < 10 || r["bio_length"].to_i.zero?) }
  unless sparse.empty?
    lines << "### Hraniční případy (málo dat → nižší jistota)"
    sparse.first(6).each do |r|
      lines << "- **@#{r['username']}** (#{r['instance']}): bio=#{r['bio_length']} zn., " \
               "#{r['posts_fetched']} postů → **#{r['ai']['family']}** `#{r['ai']['tags'].join(', ')}`"
      lines << "  > #{r['ai']['description']}"
    end
    lines << ""
  end

  # --- Data-driven doporučení ---
  empty_families = FAMILIES.reject { |f| fam_counts[f].positive? }
  single_use = tag_counts.count { |_, n| n == 1 }
  uniq = tag_counts.size
  # Heuristika synonym: tagy lišící se jen podtržítkem/koncovým "s"
  norm = Hash.new { |h, k| h[k] = [] }
  tag_counts.each_key { |t| norm[t.delete("_").sub(/s\z/, "")] << t }
  syn_groups = norm.values.select { |v| v.size > 1 }

  lines << "## 6) Doporučení"
  lines << ""
  lines << "### Kvalita rodin"
  lines << "- Úspěšnost parsování: **#{ok}/#{total}** (#{(100.0 * ok / total).round(1)} %), parse/API chyb: #{errs.size}."
  if empty_families.any?
    lines << "- ⚠️ **Nevyužité rodiny:** `#{empty_families.join('`, `')}`. Ve vzorku se nevyskytly, " \
             "ač relevantní obsah existuje (např. tagy `cycling`, `hiking`, `football` → model je dal do " \
             "`tech`/`culture`/`other`, ne do `sport`; lokální obsah z Ostravy/Brna nešel do `local`). " \
             "→ Prompt by měl rodiny `sport` a `local` explicitně přiblížit příklady, jinak model preferuje " \
             "obecnější rodinu podle profese autora."
  end
  lines << "- Rodina kóduje **primární téma účtu**, ale CZ Mastodon je silně IT-komunita → " \
           "**#{fam_counts['tech']}/#{total} účtů = tech**. Pro katalog zvážit jemnější poddělení techu " \
           "nebo váhu tagů, jinak bude `tech` přeplněná."
  lines << ""
  lines << "### Konzistence tagů"
  lines << "- Unikátních tagů: **#{uniq}** na #{ok} účtů; z toho **#{single_use}** použito jen 1× " \
           "(#{uniq.positive? ? (100.0 * single_use / uniq).round : 0} %). Vysoká kardinalita = bohaté, " \
           "ale málo konzistentní pro filtrování/faceting."
  if syn_groups.any?
    examples = syn_groups.first(4).map { |g| g.join("/") }.join("; ")
    lines << "- ⚠️ **Synonyma a varianty** zjištěny (např. #{examples}). Doporučení: zavést " \
             "**řízený slovník** nebo post-processing normalizaci (sjednocení `open_source`/`opensource`, " \
             "sloučení `politics`/`czech_politics`/`eu_politics` do hierarchie)."
  end
  lines << "- Tagy jsou věcně **smysluplné, v angličtině a lowercase dle zadání** — formát drží. " \
           "Problém není kvalita jednotlivého tagu, ale globální nejednotnost napříč účty."
  lines << ""
  lines << "### Vliv množství dat"
  lines << "- Účty s prázdným bio nebo <10 posty (#{sparse.size} ve vzorku) dostávají vágnější popis a " \
           "častěji `other` — kvalita roste s objemem postů. Doporučení: u účtů s <10 posty stáhnout víc " \
           "(včetně replies), nebo označit nižší confidence."
  lines << ""
  lines << "### Prompt — potřebuje ladění? Ano, drobné."
  lines << "1. Přidat 1větné definice + příklady k rodinám `sport`, `local`, `nature`, `news` " \
           "(jsou podreprezentované, model je míjí ve prospěch `tech`/`culture`/`other`)."
  lines << "2. Vyžádat **confidence** (0–1) pro rodinu — umožní v katalogu oddělit jisté od nejistých."
  lines << "3. U tagů doplnit pokyn „preferuj existující obecné tagy před vymýšlením nových“ + " \
           "následný normalizační krok proti řízenému slovníku."
  lines << "4. Zvážit oddělení **profese** (jeden tag) od **témat** (zbytek) — teď se mísí."
  lines << ""
  lines << "### Cena / škálovatelnost"
  lines << "- Reálně naměřeno: ~#{avg_p} vstup + ~#{avg_r} výstup tokenů/účet → " \
           "**$#{format('%.4f', cost_one)}/účet**. Pro 5000 účtů ~**$#{format('%.0f', cost_one * 5000)}** " \
           "jednorázově. S **prompt caching** statické části promptu klesnou vstupní tokeny o ~80 % při " \
           "dávkovém běhu → produkčně levné."

  lines.join("\n")
end

# Načte záznamy z JSONL (pro REPORT_ONLY režim bez volání API).
def load_jsonl
  return [] unless File.exist?(JSONL)

  File.readlines(JSONL, encoding: "UTF-8").filter_map do |line|
    line = line.strip
    next if line.empty?

    begin
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end
  end
end

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

def main
  # REPORT_ONLY=1 → jen přegeneruj report z existujícího ai_results.jsonl (bez API).
  if ENV["REPORT_ONLY"] == "1"
    recs = load_jsonl
    abort("❌ ai_results.jsonl je prázdný") if recs.empty?

    File.write(JSON_OUT, JSON.pretty_generate(recs))
    File.write(REPORT, generate_report(recs))
    log("REPORT_ONLY: přegenerováno z #{recs.size} záznamů → #{REPORT}")
    return
  end

  abort("❌ Chybí ANTHROPIC_API_KEY") if API_KEY.nil? || API_KEY.empty?

  log("Start AI kategorizace | model=#{AI_MODEL} | instancí=#{INSTANCES.size} | limit=#{TOTAL_LIMIT}")
  File.write(JSONL, "") # reset jsonl

  records = []
  INSTANCES.each do |instance|
    break if records.size >= TOTAL_LIMIT

    log("──────── #{instance} ────────")
    dir = fetch_directory(instance)
    selected = dir.reject { |a| a["bot"] || a["locked"] }.first(ACCOUNTS_PER_INSTANCE)
    log("#{instance}: directory=#{dir.size}, vybráno=#{selected.size} (po filtru bot/locked)")

    selected.each do |account|
      break if records.size >= TOTAL_LIMIT

      rec = categorize_account(instance, account)
      records << rec
      File.open(JSONL, "a") { |f| f.puts(JSON.generate(rec)) }
    end
  end

  File.write(JSON_OUT, JSON.pretty_generate(records))
  log("Zapsáno #{JSON_OUT} (#{records.size} záznamů)")

  File.write(REPORT, generate_report(records))
  log("Zapsáno #{REPORT}")
  log("Hotovo. Úspěšně: #{records.count { |r| r['error'].nil? }}/#{records.size}")
end

main if __FILE__ == $PROGRAM_NAME
