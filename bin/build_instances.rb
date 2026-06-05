#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# bin/build_instances.rb — přehled CZ/SK instancí pro tab „Instance".
#
# Pro každou instanci z config/instances.txt stáhne /api/v2/instance (+ v1 pro
# souhrnné statistiky) a sestaví web/instances.json: název, popis, logo, počet
# uživatelů, aktivní/měs, počet postů, stav registrací, jazyky, verze + kolik je
# tam našich katalogových účtů (data.json). Klient z toho vykreslí karty.
#
# Spuštění:  ruby bin/build_instances.rb [--no-upload]
# =============================================================================

require "json"
require "set"
require_relative "../lib/config"
require_relative "../lib/mastodon_api"

OUT_PATH     = File.join(Paths::WEB_DIR, "instances.json")
CATALOG_PATH = File.join(Paths::WEB_DIR, "data.json")
TOPICS_PATH  = File.join(Paths::DATA_DIR, "instance_topics.json")
# Obecné instance (mimo instances.txt) zahrň, jen když na nich máme aspoň tolik
# katalogových účtů — ať se vyhneme dlouhému ocasu jednorázových instancí.
MIN_CATALOG  = (ENV["MIN_CATALOG"] || "3").to_i

# Bridge/ne-instance, které do adresáře „kde si založit účet" nepatří.
def bridge?(host)
  host.end_with?(".brid.gy") || %w[flipboard.com bsky.brid.gy].include?(host)
end

def log(msg)
  puts "#{Time.now.strftime('%H:%M:%S')} #{msg}"
  $stdout.flush
end

API = MastodonAPI.new(logger: method(:log))

# Zaměření (oblast) instancí z cache, kterou plní bin/classify_instances.rb.
# host => [kategorie…]. Tenhle skript AI nevolá — jen čte hotové výsledky.
def topics_map
  return {} unless File.exist?(TOPICS_PATH)

  JSON.parse(File.read(TOPICS_PATH, encoding: "UTF-8"))
      .to_h { |host, v| [host.to_s.downcase, Array(v["categories"])] }
rescue StandardError
  {}
end

# Počet katalogových účtů per instance (z data.json).
def catalog_counts
  return {} unless File.exist?(CATALOG_PATH)

  counts = Hash.new(0)
  JSON.parse(File.read(CATALOG_PATH, encoding: "UTF-8")).each do |r|
    id = r["id"].to_s
    counts[id.split("@", 2).last] += 1 if id.include?("@")
  end
  counts
rescue StandardError
  {}
end

def reg_status(v2)
  reg = v2 && v2["registrations"]
  return nil unless reg.is_a?(Hash)
  return "closed" unless reg["enabled"]

  reg["approval_required"] ? "approval" : "open"
end

# Stáhne /api/v2 (+v1) instance. Když holá doména nevrací API, zkusí ještě
# mastodon.<doména> (servery běžící na subdoméně). Vrací [api_host, v2, v1] / nil.
def fetch_instance(host)
  candidates = [host]
  candidates << "mastodon.#{host}" unless host.start_with?("mastodon.")
  candidates.each do |h|
    _, v2, = API.get(h, "/api/v2/instance")
    _, v1, = API.get(h, "/api/v1/instance")
    return [h, v2, v1] if v2.is_a?(Hash) || v1.is_a?(Hash)
  end
  nil
end

def build(host, cat)
  got = fetch_instance(host)
  return nil unless got

  api_host, v2, v1 = got
  v2 ||= {}
  v1 ||= {}
  stats = v1["stats"] || {}
  desc = MastodonAPI.strip_html((v2["description"] || v1["short_description"] || v1["description"]).to_s).strip
  thumb = v2.dig("thumbnail", "url") || v1["thumbnail"]
  {
    "host" => api_host,
    "title" => (v2["title"] || v1["title"] || api_host),
    "description" => desc[0, 240],
    "thumbnail" => thumb,
    "users" => stats["user_count"],
    "statuses" => stats["status_count"],
    "active_month" => v2.dig("usage", "users", "active_month"),
    "registrations" => reg_status(v2),
    "languages" => (v2["languages"] || v1["languages"] || []),
    "version" => (v2["version"] || v1["version"]),
    "catalog_count" => (cat[api_host] || cat[host] || 0),
  }
end

def main
  czsk = CatalogConfig.read_list("instances.txt", env_key: "INSTANCES_FILE")
  feeds = CatalogConfig.read_list("feeds.txt", env_key: "FEEDS_FILE")
  czsk += feeds   # „obsahové" CZ instance (boti/zprávy) patří taky do adresáře
  czsk_set = czsk.to_set
  cat = catalog_counts
  topics = topics_map

  # Obecné instance s českými/slovenskými účty (z katalogu), mimo CZ/SK a bridge.
  extra = cat.select { |host, n| n >= MIN_CATALOG && !czsk_set.include?(host) && !bridge?(host) }
             .keys.sort_by { |h| -cat[h] }
  feeds_set = feeds.to_set
  hosts = czsk + extra
  log("Build instances | CZ/SK: #{czsk.size} (vč. feeds #{feeds.size}) + obecné s ≥#{MIN_CATALOG} účty: #{extra.size}")

  list = []
  hosts.each do |host|
    rec = build(host, cat)
    if rec
      rec["czsk"] = czsk_set.include?(host)   # dle původní domény z konfigurace
      rec["feed"] = feeds_set.include?(host)  # „obsahová" instance (boti/zprávy)
      rh = rec["host"].downcase
      rec["categories"] = topics[rh] || topics[host.downcase] || []
      list << rec
      moved = rec["host"] == host ? "" : " (→ #{rec['host']})"
      log("  ✅ #{host}#{moved}#{rec['czsk'] ? '' : ' (obecná)'}: #{rec['users'] || '?'} uživ., katalog=#{rec['catalog_count']}")
    else
      log("  ❌ #{host}: nedostupné")
    end
  end

  list.uniq! { |i| i["host"] }   # fallback mohl dvě domény srazit na stejný host
  # Řazení: CZ/SK napřed (dle uživatelů), pak obecné (dle počtu našich účtů).
  list.sort_by! { |i| [i["czsk"] ? 0 : 1, i["czsk"] ? -(i["users"] || 0) : -(i["catalog_count"] || 0)] }
  result = { "generated_at" => Time.now.utc.iso8601, "count" => list.size, "instances" => list }
  File.write("#{OUT_PATH}.tmp", JSON.generate(result))
  File.rename("#{OUT_PATH}.tmp", OUT_PATH)
  log("✅ Hotovo: #{list.size} instancí → #{OUT_PATH} (#{(File.size(OUT_PATH) / 1024.0).round} KB)")

  if ARGV.include?("--no-upload")
    log("⏭  --no-upload → instances.json zůstává jen lokálně.")
  else
    Surfer.upload(OUT_PATH, logger: method(:log))
  end
end

main if __FILE__ == $PROGRAM_NAME
