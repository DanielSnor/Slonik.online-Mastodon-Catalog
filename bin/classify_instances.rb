#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# bin/classify_instances.rb — zaměření (oblast) instancí pro tab „Instance".
#
# Mastodon API nemá pole „kategorie instance", takže zaměření odvozujeme:
#   1) PRIMÁRNĚ z oficiálního katalogu joinmastodon.org (api.joinmastodon.org)
#      — kurátorované kategorie tam, kde se instance sama přihlásila.
#   2) KDE CHYBÍ → AI klasifikace popisu instance (jak se sama identifikuje)
#      do STEJNÉHO číselníku kategorií (lib/ai). Volá se jen pro nové/změněné
#      popisy (cache podle hash popisu) → opakované běhy jsou skoro zdarma.
#
# Výstup je CACHE: data/instance_topics.json  (host => {categories, source, desc_hash}).
# Z ní pak bin/build_instances.rb (denně, BEZ AI klíče) připne `categories`
# do web/instances.json. Tenhle skript běží zřídka (týdně / ručně).
#
# Zdroj hostů + popisů: web/instances.json (vytvoří build_instances.rb).
# Pořadí při prvním nasazení:
#   ruby bin/build_instances.rb     # vytvoří instances.json (zatím bez kategorií)
#   ruby bin/classify_instances.rb  # naplní cache
#   ruby bin/build_instances.rb     # připne kategorie + upload
#
# Spuštění:  ANTHROPIC_API_KEY=… ruby bin/classify_instances.rb [--dry-run] [--rebuild]
# ENV: ANTHROPIC_API_KEY (jen pro AI fallback), AI_MODEL, MASTODON_DELAY.
# =============================================================================

require "json"
require "set"
require "digest"
require_relative "../lib/config"
require_relative "../lib/mastodon_api"
require_relative "../lib/ai"

INSTANCES_JSON = File.join(Paths::WEB_DIR, "instances.json")
TOPICS_PATH    = File.join(Paths::DATA_DIR, "instance_topics.json")
JM_HOST        = "api.joinmastodon.org"
DRY_RUN        = ARGV.include?("--dry-run")
REBUILD        = ARGV.include?("--rebuild")   # přepočítej i to, co je v cache

# Kanonický číselník = kategorie joinmastodon.org. AI klasifikuje do STEJNÉ sady.
VALID_CATEGORIES = %w[
  general academia activism art books food furry games journalism lgbt music regional tech
].freeze
MAX_CATS = 2   # max kategorií na instanci (ať je filtr přehledný)

def log(msg)
  puts "#{Time.now.strftime('%H:%M:%S')} #{msg}"
  $stdout.flush
end

API = MastodonAPI.new(logger: method(:log))

# Statický system prompt (kvůli prompt cachingu) — definice kategorií + few-shot.
AI_SYSTEM = <<~SYS
  Jsi klasifikátor ZAMĚŘENÍ Mastodon instancí (serverů) pro český/slovenský katalog.
  Dostaneš název a popis instance (jak se sama prezentuje). Zařaď instanci do 1–2
  kategorií z PEVNÉHO číselníku níže podle toho, na co se instance tematicky zaměřuje.
  Když je obecná / bez jasného zaměření, vrať "general". Odpovídáš VÝHRADNĚ JSON.

  ## Kategorie (použij přesně tyto anglické kódy)
  - general    = obecná instance bez úzkého zaměření, pro kohokoli
  - academia   = akademická obec, univerzity, výzkum, vědci, školství
  - activism   = aktivismus, lidská práva, neziskovky, společenské kampaně
  - art        = umění, výtvarná tvorba, ilustrace, fotografie jako tvorba, design
  - books      = knihy, literatura, čtenáři, autoři, nakladatelství
  - food       = jídlo, vaření, gastronomie, pití
  - furry      = furry komunita
  - games      = hry, videohry, herní komunita, gaming
  - journalism = média, novinařina, zpravodajství, redakce
  - lgbt       = LGBTQ+ komunita, queer prostor
  - music      = hudba, hudebníci, kapely, hudební scéna
  - regional   = lokální/regionální komunita (město, kraj, země) bez jiného zaměření
  - tech       = technologie, IT, software, programování, open source, self-hosting

  ## Pravidla
  - Vyber 1, nanejvýš 2 kategorie. Když si nejsi jistý, vrať ["general"].
  - "regional" zvol jen u instancí vázaných na místo BEZ jiného silného tématu.
  - Nevymýšlej kódy mimo seznam.

  ## Příklady
  Název: "Linux & FOSS komunita", popis: "Server pro fanoušky Linuxu, self-hostingu a open source."
  → {"categories": ["tech"]}
  Název: "Queer.cz", popis: "Bezpečný prostor pro LGBT+ lidi a jejich spojence."
  → {"categories": ["lgbt"]}
  Název: "Mastodon Brno", popis: "Instance pro lidi z Brna a okolí, místní dění."
  → {"categories": ["regional"]}
  Název: "Naše instance", popis: "Otevřená instance pro kohokoli, žádné konkrétní téma."
  → {"categories": ["general"]}

  ## Výstup
  Pouze jeden JSON objekt, bez markdownu: {"categories": ["...", "..."]}
SYS

# Stáhne katalog joinmastodon → { "domain" => [kategorie…] } (jen platné kódy).
def joinmastodon_map
  code, arr, = API.get(JM_HOST, "/servers")
  unless code == 200 && arr.is_a?(Array)
    log("  ⚠️  joinmastodon nedostupné (HTTP #{code}) → jedeme jen z AI")
    return {}
  end
  map = {}
  arr.each do |s|
    host = s["domain"].to_s.downcase
    next if host.empty?

    cats = Array(s["categories"])
    cats << s["category"] if cats.empty? && s["category"]
    cats = cats.map { |c| c.to_s.downcase }.select { |c| VALID_CATEGORIES.include?(c) }.uniq.first(MAX_CATS)
    map[host] = cats unless cats.empty?
  end
  log("  joinmastodon: #{arr.size} serverů, z toho #{map.size} s kategoriemi")
  map
end

def load_cache
  return {} if REBUILD || !File.exist?(TOPICS_PATH)

  JSON.parse(File.read(TOPICS_PATH, encoding: "UTF-8"))
rescue StandardError
  {}
end

# Hosty + popisy bereme z hotového instances.json (vytvoří build_instances.rb).
def read_instances
  unless File.exist?(INSTANCES_JSON)
    log("❌ #{INSTANCES_JSON} neexistuje — spusť nejdřív: ruby bin/build_instances.rb")
    exit 1
  end
  (JSON.parse(File.read(INSTANCES_JSON, encoding: "UTF-8"))["instances"] || [])
rescue StandardError => e
  log("❌ instances.json nelze načíst: #{e.class}: #{e.message}")
  exit 1
end

def ai_categorize(ai, title, desc)
  prompt = "Název instance: #{title}\n\nPopis instance:\n#{desc}\n"
  res = ai.call(prompt, system: AI_SYSTEM)
  return nil if res[:error]

  parsed = ai.parse_json(res[:text])
  return nil unless parsed

  cats = Array(parsed["categories"]).map { |c| c.to_s.downcase.strip }
                                    .select { |c| VALID_CATEGORIES.include?(c) }.uniq.first(MAX_CATS)
  cats.empty? ? ["general"] : cats
end

def main
  insts = read_instances
  cache = load_cache
  jm = joinmastodon_map
  ai = AI.new(logger: method(:log))
  have_key = !ai.instance_variable_get(:@api_key).to_s.empty?

  log("Klasifikace zaměření: #{insts.size} instancí | joinmastodon=#{jm.size} | AI klíč=#{have_key} | rebuild=#{REBUILD}")
  stats = Hash.new(0)

  insts.each do |i|
    host = i["host"].to_s.downcase
    next if host.empty?

    if jm[host] && !jm[host].empty?
      cache[host] = { "categories" => jm[host], "source" => "joinmastodon", "desc_hash" => nil }
      stats[:joinmastodon] += 1
      next
    end

    desc = "#{i['title']} #{i['description']}".strip
    dhash = Digest::SHA1.hexdigest(desc)
    cached = cache[host]
    if !REBUILD && cached && cached["source"] != "joinmastodon" &&
       cached["desc_hash"] == dhash && !Array(cached["categories"]).empty?
      stats[:cached] += 1
      next   # popis se nezměnil → necháme z cache (žádné AI volání)
    end

    unless have_key
      stats[:skipped_nokey] += 1
      next
    end

    cats = ai_categorize(ai, i["title"].to_s, i["description"].to_s) || ["general"]
    cache[host] = { "categories" => cats, "source" => "ai", "desc_hash" => dhash }
    stats[:ai] += 1
    log("  🤖 #{host} → #{cats.join(', ')}")
  end

  log("Hotovo: joinmastodon=#{stats[:joinmastodon]} ai=#{stats[:ai]} z_cache=#{stats[:cached]} bez_klíče=#{stats[:skipped_nokey]}")

  if DRY_RUN
    log("⏭  --dry-run → cache se nezapisuje.")
    return
  end
  File.write("#{TOPICS_PATH}.tmp", JSON.pretty_generate(cache))
  File.rename("#{TOPICS_PATH}.tmp", TOPICS_PATH)
  log("✅ Cache → #{TOPICS_PATH} (#{cache.size} instancí)")
  log("ℹ️  Spusť teď ruby bin/build_instances.rb, ať se kategorie připnou do instances.json.")
end

main if __FILE__ == $PROGRAM_NAME
