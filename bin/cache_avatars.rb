#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# cache_avatars.rb — lokální kopie avatarů katalogu.
#
# PROČ. Avatary se dosud načítaly přímo z domovských instancí, takže:
#   • ~65 cizích serverů vidělo IP adresu každého návštěvníka,
#   • prohlížeč stahoval obrázky 400×400 px (medián 25 kB, p90 207 kB), aby je
#     vykreslil na 56 px — celý seznam Účtů znamenal skoro 40 MB přenosu.
# Zmenšená kopie na vlastní doméně řeší obojí naráz: ~2–4 kB na avatar, jedno
# spojení, a nikdo třetí se o návštěvníkovi nedozví.
#
# JAK. Jméno souboru je hash ZDROJOVÉ URL. Mastodon má v URL obsahový hash
# obrázku, takže nezměněná URL = nezměněný obrázek → další běhy nestahují nic.
# Změna avataru dá novou URL → nový soubor → starý se prořeže. Žádné
# cache-busting hlavičky nejsou potřeba.
#
# ZÁVISLOST je měkká: potřebuje `vipsthumbnail` (nebo `magick`/`convert`).
# Když žádný není, skript skončí bez chyby a web dál používá vzdálené URL.
#
# Spuštění:
#   ruby bin/cache_avatars.rb              # doplní chybějící, prořeže, nahraje
#   ruby bin/cache_avatars.rb --dry-run    # jen spočítá, co by udělal
#   ruby bin/cache_avatars.rb --no-upload  # jen lokálně
#   ruby bin/cache_avatars.rb --rebuild    # zahodí cache a udělá ji znovu
#   LIMIT=50 ruby bin/cache_avatars.rb     # jen prvních N nových (ladění)
#
# ENV: AVATAR_SIZE (112), AVATAR_QUALITY (80), AVATAR_DIR (web/avatars),
#      CATALOG_PATH, PUBLIC_CATALOG_PATH, LIMIT, SURFER_* (viz config.env).
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

CATALOG_PATH = ENV["CATALOG_PATH"] || Paths.catalog_source
PUBLIC_PATH  = ENV["PUBLIC_CATALOG_PATH"] || Paths::CATALOG_PUBLIC
AVATAR_DIR   = ENV["AVATAR_DIR"] || File.join(Paths::WEB_DIR, "avatars")
# 112 px = dvojnásobek 56px slotu v kartě (retina). Větší nemá co zobrazit.
AVATAR_SIZE    = (ENV["AVATAR_SIZE"] || "112").to_i
AVATAR_QUALITY = (ENV["AVATAR_QUALITY"] || "80").to_i
LIMIT          = (ENV["LIMIT"] || "0").to_i
MAX_BYTES      = (ENV["AVATAR_MAX_BYTES"] || "10485760").to_i # 10 MB strop na stahování
MAX_REDIRECTS  = 3

def log(msg)
  puts "#{Time.now.strftime('%H:%M:%S')} #{msg}"
  $stdout.flush
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
def thumbnail(src, dest)
  kind, bin = thumbnailer
  ok =
    case kind
    when :vips
      system(bin, src, "--size", "#{AVATAR_SIZE}x#{AVATAR_SIZE}",
             "-o", "#{dest}[Q=#{AVATAR_QUALITY}]",
             out: File::NULL, err: File::NULL)
    when :magick
      system(bin, "#{src}[0]", "-resize", "#{AVATAR_SIZE}x#{AVATAR_SIZE}>",
             "-quality", AVATAR_QUALITY.to_s, dest,
             out: File::NULL, err: File::NULL)
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
  req["User-Agent"] = MastodonAPI::USER_AGENT if defined?(MastodonAPI)
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

def main
  unless File.exist?(CATALOG_PATH)
    abort("❌ Katalog nenalezen: #{CATALOG_PATH}")
  end

  unless thumbnailer
    log("ℹ️  Není k dispozici vipsthumbnail ani ImageMagick → cachování přeskočeno.")
    log("   Web bude dál používat vzdálené URL avatarů (funkční, jen bez úspory a soukromí).")
    return
  end
  kind, bin = thumbnailer
  log("Cache avatarů | #{AVATAR_SIZE}px WebP q#{AVATAR_QUALITY} | nástroj: #{kind} (#{bin})")

  catalog = Catalog.load(CATALOG_PATH)
  FileUtils.rm_rf(AVATAR_DIR) if REBUILD && !DRY_RUN
  FileUtils.mkdir_p(AVATAR_DIR) unless DRY_RUN

  wanted = {}   # jméno souboru => zdrojová URL
  catalog.each do |rec|
    url = rec["avatar"].to_s
    next unless url.start_with?("https://")

    wanted[cache_name(url)] = url
  end

  have = Dir.exist?(AVATAR_DIR) ? Dir.children(AVATAR_DIR).to_set : Set.new
  missing = wanted.reject { |name, _| have.include?(name) }
  missing = missing.first(LIMIT).to_h if LIMIT.positive?
  stale = have - wanted.keys.to_set

  log("Účtů s avatarem: #{wanted.size} | v cache: #{(wanted.keys.to_set & have).size} | " \
      "ke stažení: #{missing.size} | k prořezání: #{stale.size}")

  if DRY_RUN
    log("⚠️  DRY-RUN — nic se nestahuje ani nemaže.")
    return
  end

  # 1) Stáhni a zmenši chybějící
  done = failed = 0
  bytes_in = bytes_out = 0
  missing.each_with_index do |(name, url), i|
    data = fetch_image(url)
    unless data
      failed += 1
      next
    end

    tmp = File.join(AVATAR_DIR, ".#{name}.src")
    File.binwrite(tmp, data)
    dest = File.join(AVATAR_DIR, name)
    if thumbnail(tmp, dest)
      bytes_in += data.bytesize
      bytes_out += File.size(dest)
      done += 1
    else
      failed += 1
    end
    File.delete(tmp) if File.exist?(tmp)

    log("  … #{i + 1}/#{missing.size} (hotovo #{done}, chyb #{failed})") if ((i + 1) % 100).zero?
  end
  if done.positive?
    log("  Staženo a zmenšeno: #{done} | chyb: #{failed} | " \
        "#{(bytes_in / 1_048_576.0).round(1)} MB → #{(bytes_out / 1_048_576.0).round(2)} MB " \
        "(#{(100 - 100.0 * bytes_out / bytes_in).round} % úspora)")
  end

  # 2) Prořež, co už katalog nepoužívá. Tohle je zároveň cesta, kterou z webu
  #    zmizí avatar účtu vyřazeného blocklistem — z katalogu vypadl, takže na
  #    jeho soubor nikdo neukazuje.
  pruned = 0
  stale.each do |name|
    File.delete(File.join(AVATAR_DIR, name))
    pruned += 1
  end
  log("  Prořezáno nepoužívaných: #{pruned}") if pruned.positive?

  # 3) Propiš cesty do katalogu. Účet bez použitelné kopie zůstane bez
  #    `avatar_local` → frontend u něj sáhne po vzdálené URL jako dřív.
  present = Dir.children(AVATAR_DIR).to_set
  linked = 0
  catalog.each do |rec|
    url = rec["avatar"].to_s
    name = url.start_with?("https://") ? cache_name(url) : nil
    if name && present.include?(name)
      rec["avatar_local"] = "avatars/#{name}"
      linked += 1
    else
      rec.delete("avatar_local")
    end
  end
  Catalog.write_json(CATALOG_PATH, catalog)
  Catalog.publish(catalog, PUBLIC_PATH)
  log("  Katalog: #{linked}/#{catalog.size} účtů má lokální avatar")

  total = present.sum { |n| File.size(File.join(AVATAR_DIR, n)) }
  log("  Cache celkem: #{present.size} souborů, #{(total / 1_048_576.0).round(1)} MB")

  # 4) Upload na Surfer — jen nové soubory a mazání prořezaných.
  if NO_UPLOAD
    log("⏭  --no-upload → zůstává jen lokálně.")
    return
  end
  unless Surfer.configured?
    log("ℹ️  Surfer nenakonfigurován → upload přeskočen.")
    return
  end

  up_ok = up_err = 0
  missing.each_key do |name|
    path = File.join(AVATAR_DIR, name)
    next unless File.exist?(path)

    Surfer.upload(path, logger: method(:log), subdir: "avatars", quiet: true) == :ok ? up_ok += 1 : up_err += 1
  end
  del_ok = 0
  stale.each { |name| del_ok += 1 if %i[ok missing].include?(Surfer.delete(name, logger: method(:log), subdir: "avatars")) }
  log("  Upload: nahráno #{up_ok}, chyb #{up_err}, smazáno #{del_ok}")

  Surfer.upload(PUBLIC_PATH, logger: method(:log))
end

main if __FILE__ == $PROGRAM_NAME
