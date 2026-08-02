#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# check_sri.rb — hlídač otisků externích skriptů (Subresource Integrity).
#
# PROČ. index.html načítá jeden skript z cizí domény (měření návštěvnosti) a má
# u něj `integrity="sha384-…"`. Ten otisk je obrana proti podvržení: kdyby někdo
# cizí host kompromitoval, prohlížeč skript nespustí.
#
# Má to ale tichou stranu. Když provozovatel službu upgraduje, obsah souboru se
# změní, otisk přestane sedět — a prohlížeč skript přestane spouštět. Web běží
# dál, jen se **tiše zastaví měření**. Pozná se to až podle rovné čáry
# ve statistikách, klidně za měsíc.
#
# Tenhle skript to chytí do týdne: stáhne každý externí zdroj s `integrity`,
# přepočítá otisk a porovná. Při neshodě vypíše nový otisk k zkopírování
# a skončí s nenulovým návratovým kódem, takže to weekly.sh označí jako selhání.
#
# Hlídá i opačný směr: externí skript BEZ `integrity` je přesně ten stav, kvůli
# kterému otisky vznikly, takže se taky hlásí jako chyba.
#
# Spuštění:
#   ruby bin/check_sri.rb            # ověří web/index.html
#   INDEX_PATH=/jina/cesta.html ruby bin/check_sri.rb
# =============================================================================

require "base64"
require "digest"
require "net/http"
require "uri"
require_relative "../lib/paths"

INDEX_PATH    = ENV["INDEX_PATH"] || File.join(Paths::WEB_DIR, "index.html")
MAX_REDIRECTS = 3

def log(msg)
  puts "#{Time.now.strftime('%H:%M:%S')} #{msg}"
  $stdout.flush
end

# `rel`, u kterých prohlížeč soubor opravdu stáhne a použije. Ostatní <link>
# (canonical, alternate, icon…) jsou jen metadata — nic se z nich nespouští,
# takže SRI nedává smysl a hlásit je jako chybu by byl planý poplach.
SUBRESOURCE_RELS = %w[stylesheet preload modulepreload].freeze

# Vytáhne z HTML externí <script src>/<link rel=stylesheet|preload> a k nim
# hodnotu integrity (nebo nil). Čistá funkce — testuje se v test/test_sri.rb.
def external_subresources(html)
  html.scan(/<(?:script|link)\b[^>]*>/i).filter_map do |tag|
    url = tag[/\b(?:src|href)\s*=\s*["']([^"']+)["']/i, 1]
    next unless url&.start_with?("https://")

    if tag =~ /\A<link/i
      rels = tag[/\brel\s*=\s*["']([^"']+)["']/i, 1].to_s.downcase.split(/\s+/)
      next if (rels & SUBRESOURCE_RELS).empty?
    end

    { url: url, integrity: tag[/\bintegrity\s*=\s*["']([^"']+)["']/i, 1] }
  end
end

# Spočítá SRI otisk (`algo-base64`) pro daná data.
def sri_digest(algo, data)
  raw = case algo
        when "sha256" then Digest::SHA256.digest(data)
        when "sha384" then Digest::SHA384.digest(data)
        when "sha512" then Digest::SHA512.digest(data)
        end
  raw && "#{algo}-#{Base64.strict_encode64(raw)}"
end

# Sedí obsah aspoň na jeden z uvedených otisků? (SRI atribut jich může nést víc,
# stačí shoda s jedním.) Vrací [true/false, spočítané otisky].
def integrity_matches?(integrity, data)
  wanted = integrity.to_s.split(/\s+/).reject(&:empty?)
  actual = wanted.filter_map { |w| sri_digest(w.split("-", 2).first, data) }
  [wanted.any? { |w| actual.include?(w) }, actual]
end

def fetch(url, depth = 0)
  return nil if depth > MAX_REDIRECTS

  uri = URI.parse(url) rescue nil
  return nil unless uri.is_a?(URI::HTTPS)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 30
  resp = http.request(Net::HTTP::Get.new(uri))
  return fetch(URI.join(url, resp["location"]).to_s, depth + 1) if resp["location"] && resp.code.to_i.between?(300, 399)
  return nil unless resp.code.to_i == 200

  resp.body
rescue StandardError
  nil
end

def main
  unless File.exist?(INDEX_PATH)
    abort("❌ Nenalezeno: #{INDEX_PATH}")
  end

  subresources = external_subresources(File.read(INDEX_PATH, encoding: "UTF-8"))
  if subresources.empty?
    log("Žádné externí zdroje v #{File.basename(INDEX_PATH)} — nic k hlídání.")
    return 0
  end

  log("Kontrola otisků: #{subresources.size} externích zdrojů")
  problems = 0

  subresources.each do |sub|
    if sub[:integrity].to_s.empty?
      log("  ❌ #{sub[:url]}")
      log("     Externí skript BEZ integrity — doplň otisk, jinak je to volná ruka pro cizí host.")
      problems += 1
      next
    end

    data = fetch(sub[:url])
    if data.nil?
      # Nedostupný host neznamená zastaralý otisk; ohlásíme, ale nepadáme kvůli
      # tomu — výpadek cizí služby není chyba našeho nasazení.
      log("  ⚠️  #{sub[:url]}: nelze stáhnout, otisk neověřen")
      next
    end

    ok, actual = integrity_matches?(sub[:integrity], data)
    if ok
      log("  ✅ #{sub[:url]}")
    else
      log("  ❌ #{sub[:url]}: OTISK NESEDÍ → prohlížeče skript NESPOUŠTĚJÍ")
      log("     v index.html: #{sub[:integrity]}")
      log("     aktuální:     #{actual.join(' ')}")
      log("     Buď byla služba upgradována (pak otisk v index.html přepiš tím aktuálním),")
      log("     nebo se obsah změnil bez tvého vědomí — pak ho NEPŘEPISUJ a zjisti proč.")
      problems += 1
    end
  end

  problems.zero? ? 0 : 1
end

exit(main) if __FILE__ == $PROGRAM_NAME
