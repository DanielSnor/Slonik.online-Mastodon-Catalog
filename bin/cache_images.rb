#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# cache_images.rb — lokální kopie obrázků, které web zobrazuje z cizích serverů.
#
# PROČ. Avatary účtů i loga instancí se dosud načítaly přímo z domovských
# serverů, takže:
#   • ~65 cizích serverů vidělo IP adresu každého návštěvníka,
#   • prohlížeč stahoval obrázky mnohonásobně větší, než kolik vykreslí.
#     Avatary: 400×400 px (medián 25 kB, p90 207 kB) na 56px slot → seznam Účtů
#     skoro 40 MB. Loga: bannery 1200×620 (průměr 366 kB) na 60px slot → 13,5 MB
#     za 38 instancí.
# Zmenšená kopie na vlastní doméně řeší obojí naráz: jednotky kB, jedno spojení,
# a nikdo třetí se o návštěvníkovi nedozví.
#
# JAK. Jméno souboru je hash ZDROJOVÉ URL. Mastodon má v URL obsahový hash
# obrázku, takže nezměněná URL = nezměněný obrázek → další běhy nestahují nic.
# Změna obrázku dá novou URL → nový soubor → starý se prořeže. Žádné
# cache-busting hlavičky nejsou potřeba.
#
# POŘADÍ. Skript musí běžet AŽ ZA update_catalog i refresh-instances — čte jejich
# výstupy a zapisuje do nich cesty ke kopiím. build_instances.rb navíc staví
# instances.json pokaždé od nuly, takže `thumbnail_local` v něm nepřežije; tenhle
# skript ho pokaždé doplní znovu (a je tím sám od sebe samoopravný).
#
# ZÁVISLOST je měkká: potřebuje `vipsthumbnail` (nebo `magick`/`convert`).
# Když žádný není, skript skončí bez chyby a web dál používá vzdálené URL.
#
# Spuštění:
#   ruby bin/cache_images.rb              # doplní chybějící, prořeže, nahraje
#   ruby bin/cache_images.rb --dry-run    # jen spočítá, co by udělal
#   ruby bin/cache_images.rb --no-upload  # jen lokálně
#   ruby bin/cache_images.rb --rebuild    # zahodí cache a udělá ji znovu
#   ruby bin/cache_images.rb --only logos # jen jeden druh (avatars|logos)
#   LIMIT=50 ruby bin/cache_images.rb     # jen prvních N nových (ladění)
#
# ENV: AVATAR_SIZE (112), LOGO_SIZE (120), IMAGE_QUALITY (80), LIMIT,
#      CATALOG_PATH, PUBLIC_CATALOG_PATH, INSTANCES_PATH, SURFER_* (config.env).
# =============================================================================

require "digest"
require "fileutils"
require "json"
require "net/http"
require "set"
require "uri"
require_relative "../lib/config"
require_relative "../lib/catalog"

DRY_RUN   = ARGV.include?("--dry-run")
NO_UPLOAD = ARGV.include?("--no-upload")
REBUILD   = ARGV.include?("--rebuild")
ONLY      = (ARGV[ARGV.index("--only") + 1] if ARGV.include?("--only"))

CATALOG_PATH   = ENV["CATALOG_PATH"] || Paths.catalog_source
PUBLIC_PATH    = ENV["PUBLIC_CATALOG_PATH"] || Paths::CATALOG_PUBLIC
INSTANCES_PATH = ENV["INSTANCES_PATH"] || File.join(Paths::WEB_DIR, "instances.json")

IMAGE_QUALITY = (ENV["IMAGE_QUALITY"] || "80").to_i
LIMIT         = (ENV["LIMIT"] || "0").to_i
MAX_BYTES     = (ENV["IMAGE_MAX_BYTES"] || "10485760").to_i # 10 MB strop na stahování
MAX_REDIRECTS = 3

def log(msg)
  puts "#{Time.now.strftime('%H:%M:%S')} #{msg}"
  $stdout.flush
end

# ---------------------------------------------------------------------------
# Zdroje obrázků
# ---------------------------------------------------------------------------
#
# Každý zdroj ví, odkud číst záznamy, které pole nese vzdálenou adresu, jak
# velkou kopii chceme a jak výsledek zapsat zpět.
#
# `crop`: avatary jsou čtvercové, takže stačí zmenšit. Loga jsou bannery
# (1200×620) zobrazené jako čtverec s `object-fit: cover`, tedy oříznuté doprostřed
# — kopie proto musí být ořezaná stejně, aby se vzhled webu nezměnil.
#
# Schválně NE `--smartcrop attention`: porovnáno na osmi reálných logách a střed
# vyhrál. U witter.cz a f.cz „attention" utne nápis, u mastodonovských log posune
# výřez a ukousne slonovi hlavu.
SOURCES = [
  {
    key: "avatars", label: "avatary účtů", field: "avatar", local_field: "avatar_local",
    size: (ENV["AVATAR_SIZE"] || "112").to_i, crop: nil,
    load: -> { Catalog.load(CATALOG_PATH) },
    save: lambda do |records|
      Catalog.write_json(CATALOG_PATH, records)
      Catalog.publish(records, PUBLIC_PATH)
      [PUBLIC_PATH]
    end,
  },
  {
    key: "logos", label: "loga instancí", field: "thumbnail", local_field: "thumbnail_local",
    size: (ENV["LOGO_SIZE"] || "120").to_i, crop: "centre",
    load: lambda do
      next [] unless File.exist?(INSTANCES_PATH)

      JSON.parse(File.read(INSTANCES_PATH, encoding: "UTF-8"))["instances"] || []
    end,
    save: lambda do |records|
      doc = JSON.parse(File.read(INSTANCES_PATH, encoding: "UTF-8"))
      doc["instances"] = records
      Catalog.write_json(INSTANCES_PATH, doc, pretty: false)
      [INSTANCES_PATH]
    end,
  },
].freeze

def image_dir(src)
  File.join(Paths::WEB_DIR, src[:key])
end

# ---------------------------------------------------------------------------
# Zmenšování
# ---------------------------------------------------------------------------

# Najde dostupný nástroj. vips je první volba (nejrychlejší a nejšetrnější
# k paměti), ImageMagick jako náhrada. Vrací [:vips|:magick, cesta] nebo nil.
def thumbnailer
  return @thumbnailer if defined?(@thumbnailer)

  @thumbnailer =
    if (p = which("vipsthumbnail")) then [:vips, p]
    elsif (p = which("magick"))     then [:magick, p]
    elsif (p = which("convert"))    then [:magick, p]
    end
end

def which(bin)
  ENV["PATH"].to_s.split(File::PATH_SEPARATOR).each do |dir|
    path = File.join(dir, bin)
    return path if File.executable?(path) && !File.directory?(path)
  end
  nil
end

# Zmenší `src` do `dest` (WebP). Vrací true při úspěchu.
#
# Animované GIFy se uloží jako STATICKÝ první snímek — Mastodon sám avatary
# ve výchozím nastavení nepřehrává, takže se tím nic neztrácí a ušetří to
# řádově velikost.
def thumbnail(src, dest, size, crop)
  kind, bin = thumbnailer
  ok =
    case kind
    when :vips
      args = [src, "--size", "#{size}x#{size}"]
      args += ["--smartcrop", crop] if crop
      args += ["-o", "#{dest}[Q=#{IMAGE_QUALITY}]"]
      system(bin, *args, out: File::NULL, err: File::NULL)
    when :magick
      geom = crop ? "#{size}x#{size}^" : "#{size}x#{size}>"
      args = ["#{src}[0]", "-resize", geom]
      args += ["-gravity", "center", "-extent", "#{size}x#{size}"] if crop
      args += ["-quality", IMAGE_QUALITY.to_s, dest]
      system(bin, *args, out: File::NULL, err: File::NULL)
    end
  ok && File.exist?(dest) && File.size(dest).positive?
end

# ---------------------------------------------------------------------------
# Stahování
# ---------------------------------------------------------------------------

# Stáhne obrázek. Jen https, omezený počet přesměrování, strop na velikost
# a kontrola, že to opravdu je obrázek — URL pochází z cizí instance.
def fetch_image(url, depth = 0)
  return nil if depth > MAX_REDIRECTS

  uri = URI.parse(url) rescue nil
  return nil unless uri.is_a?(URI::HTTPS) && uri.host

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 30

  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = "mastokatalog-images/1.0 (+https://slonik.online)"
  req["Accept"] = "image/*"

  http.request(req) do |resp|
    code = resp.code.to_i
    if [301, 302, 303, 307, 308].include?(code) && resp["location"]
      return fetch_image(URI.join(url, resp["location"]).to_s, depth + 1)
    end
    return nil unless code == 200
    return nil unless resp["content-type"].to_s.start_with?("image/")

    body = +"".b
    resp.read_body do |chunk|
      body << chunk
      return nil if body.bytesize > MAX_BYTES
    end
    return body
  end
rescue StandardError
  nil
end

# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------

# Jméno souboru z hashe ZDROJOVÉ URL — viz hlavička skriptu.
def cache_name(url)
  "#{Digest::SHA1.hexdigest(url.to_s)[0, 20]}.webp"
end

# Zpracuje jeden zdroj. Vrací pole metadatových souborů, které je po změně
# potřeba znovu nahrát na Surfer.
def process(src)
  records = src[:load].call
  if records.empty?
    log("── #{src[:label]}: žádné záznamy, přeskakuji")
    return []
  end

  dir = image_dir(src)
  FileUtils.rm_rf(dir) if REBUILD && !DRY_RUN
  FileUtils.mkdir_p(dir) unless DRY_RUN

  wanted = {}   # jméno souboru => zdrojová URL
  records.each do |rec|
    url = rec[src[:field]].to_s
    next unless url.start_with?("https://")

    wanted[cache_name(url)] = url
  end

  have = Dir.exist?(dir) ? Dir.children(dir).to_set : Set.new
  missing = wanted.reject { |name, _| have.include?(name) }
  missing = missing.first(LIMIT).to_h if LIMIT.positive?
  stale = have - wanted.keys.to_set

  log("── #{src[:label]}: #{wanted.size} obrázků | v cache: #{(wanted.keys.to_set & have).size} | " \
      "ke stažení: #{missing.size} | k prořezání: #{stale.size}")
  return [] if DRY_RUN

  # 1) Stáhni a zmenši chybějící
  done = failed = 0
  bytes_in = bytes_out = 0
  missing.each_with_index do |(name, url), i|
    data = fetch_image(url)
    unless data
      failed += 1
      next
    end

    tmp = File.join(dir, ".#{name}.src")
    File.binwrite(tmp, data)
    dest = File.join(dir, name)
    if thumbnail(tmp, dest, src[:size], src[:crop])
      bytes_in += data.bytesize
      bytes_out += File.size(dest)
      done += 1
    else
      failed += 1
    end
    File.delete(tmp) if File.exist?(tmp)

    log("   … #{i + 1}/#{missing.size} (hotovo #{done}, chyb #{failed})") if ((i + 1) % 100).zero?
  end
  if done.positive?
    log("   Staženo a zmenšeno: #{done} | chyb: #{failed} | " \
        "#{(bytes_in / 1_048_576.0).round(1)} MB → #{(bytes_out / 1_048_576.0).round(2)} MB " \
        "(#{(100 - 100.0 * bytes_out / bytes_in).round} % úspora)")
  end

  # 2) Prořež, co se už nepoužívá. Tohle je zároveň cesta, kterou z webu zmizí
  #    avatar účtu vyřazeného blocklistem — z katalogu vypadl, takže na jeho
  #    soubor nikdo neukazuje.
  stale.each { |name| File.delete(File.join(dir, name)) }
  log("   Prořezáno nepoužívaných: #{stale.size}") if stale.any?

  # 3) Propiš cesty zpět. Záznam bez použitelné kopie zůstane bez lokálního pole
  #    → frontend u něj sáhne po vzdálené URL jako dřív.
  present = Dir.children(dir).to_set
  linked = 0
  records.each do |rec|
    url = rec[src[:field]].to_s
    name = url.start_with?("https://") ? cache_name(url) : nil
    if name && present.include?(name)
      rec[src[:local_field]] = "#{src[:key]}/#{name}"
      linked += 1
    else
      rec.delete(src[:local_field])
    end
  end
  to_upload = src[:save].call(records)

  total = present.sum { |n| File.size(File.join(dir, n)) }
  log("   Hotovo: #{linked}/#{records.size} záznamů má lokální kopii | " \
      "#{present.size} souborů, #{(total / 1_048_576.0).round(2)} MB")

  return [] if NO_UPLOAD || !Surfer.configured?

  # 4) Upload na Surfer — jen nové soubory a mazání prořezaných.
  up_ok = up_err = 0
  missing.each_key do |name|
    path = File.join(dir, name)
    next unless File.exist?(path)

    Surfer.upload(path, logger: method(:log), subdir: src[:key], quiet: true) == :ok ? up_ok += 1 : up_err += 1
  end
  del = stale.count { |name| %i[ok missing].include?(Surfer.delete(name, logger: method(:log), subdir: src[:key])) }
  log("   Upload: nahráno #{up_ok}, chyb #{up_err}, smazáno #{del}") if (up_ok + up_err + del).positive?

  to_upload
end

def main
  unless thumbnailer
    log("ℹ️  Není k dispozici vipsthumbnail ani ImageMagick → cachování přeskočeno.")
    log("   Web bude dál používat vzdálené URL (funkční, jen bez úspory a soukromí).")
    return
  end
  kind, bin = thumbnailer
  sources = ONLY ? SOURCES.select { |s| s[:key] == ONLY } : SOURCES
  abort("❌ Neznámý zdroj: #{ONLY} (znám: #{SOURCES.map { |s| s[:key] }.join(', ')})") if sources.empty?

  log("Cache obrázků | WebP q#{IMAGE_QUALITY} | nástroj: #{kind} (#{bin})")
  metadata = sources.flat_map { |src| process(src) }

  if DRY_RUN
    log("⚠️  DRY-RUN — nic se nestahuje ani nemaže.")
  elsif NO_UPLOAD
    log("⏭  --no-upload → zůstává jen lokálně.")
  elsif Surfer.configured?
    # Metadatové soubory (data.json, instances.json) se změnily → nahraj znovu.
    metadata.uniq.each { |path| Surfer.upload(path, logger: method(:log)) }
  else
    log("ℹ️  Surfer nenakonfigurován → upload přeskočen.")
  end
end

main if __FILE__ == $PROGRAM_NAME
