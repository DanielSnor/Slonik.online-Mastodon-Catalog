# frozen_string_literal: true

# lib/config.rb — loader konfigurace pro všechny skripty katalogu + Surfer upload.
#
# Načte `config.env` (formát KEY=value, jeden na řádek) z kořene projektu a
# nastaví hodnoty do ENV — ale JEN pokud daný klíč v ENV ještě není (skutečné
# ENV proměnné mají přednost, takže jdou config hodnoty kdykoli přebít).
#
# Použití: na začátku skriptu `require_relative "lib/config"`.
#
# Cestu ke configu lze přepsat přes ENV CONFIG_PATH. Pokud soubor neexistuje,
# loader tiše nic neudělá (skripty fungují i čistě z ENV).
#
# BEZPEČNOST: config.env obsahuje tajemství (SURFER_TOKEN, …) → patří do
# .gitignore, NIKDY se necommituje. Šablona je config.env.example.

require "net/http"
require "set"
require "uri"
require_relative "paths"

module CatalogConfig
  # config.env je v kořeni projektu (viz Paths::CONFIG_ENV).
  def self.load(path = nil)
    path ||= ENV["CONFIG_PATH"] || Paths::CONFIG_ENV
    return unless File.exist?(path)

    File.foreach(path, encoding: "UTF-8") do |raw|
      line = raw.strip
      next if line.empty? || line.start_with?("#")

      key, val = line.split("=", 2)
      next if key.nil? || val.nil?

      key = key.strip
      val = val.strip
      # Odstraň případné obklopující uvozovky.
      val = val[1..-2] if val.length >= 2 && ((val.start_with?('"') && val.end_with?('"')) ||
                                              (val.start_with?("'") && val.end_with?("'")))
      # Skutečné ENV má přednost — nepřepisuj, co už je nastaveno.
      ENV[key] ||= val
    end
  end

  # Načte řádkový datový soubor (instances.txt, seeds.txt): vrátí pole řádků
  # bez prázdných a bez komentářů (# …). Trimuje whitespace. Cestu lze přebít
  # přes ENV `env_key`; jinak hledá `basename` ve složce config/.
  # Když soubor neexistuje, vrátí [] (volající rozhodne, zda je to fatální).
  def self.read_list(basename, env_key: nil)
    path = (env_key && ENV[env_key]) || File.join(Paths::CONFIG_DIR, basename)
    return [] unless File.exist?(path)

    File.readlines(path, encoding: "UTF-8").filter_map do |raw|
      line = raw.sub(/#.*/, "").strip
      line.empty? ? nil : line
    end
  end

  # Totéž jako read_list, ale pro seznamy Mastodon HANDLŮ (blocklist.txt,
  # manual_accounts.txt): vrací Set v lowercase.
  #
  # Mastodon handle je case-insensitive (@Franta@x.cz == @franta@x.cz), takže
  # porovnávat se MUSÍ přes downcase. Jinak handle zapsaný jinou velikostí písmen
  # tiše neudělá nic — a u blocklistu to znamená nevyřízenou žádost o odstranění.
  # Volající proto porovnává `set.include?(id.downcase)`.
  def self.read_handle_set(basename, env_key: nil)
    read_list(basename, env_key: env_key).map(&:downcase).to_set
  end
end

# ---------------------------------------------------------------------------
# Sdílený upload na Surfer (Cloudron Files API) — používá consolidate i update.
#
#   POST /api/files/<remote>?access_token=TOKEN&newFilePath=<remote>
#   Content-Type: multipart/form-data, pole "file". Úspěch = HTTP 2xx (typicky 201).
#
# Konfigurace (config.env / ENV):
#   SURFER_URL, SURFER_TOKEN, SURFER_REMOTE_DIR (prázdné = root).
#
# Vrací :ok / :skipped / :failed. Logování přes blok (volitelný), aby si každý
# skript mohl použít svůj log().
module Surfer
  module_function

  def configured?
    !ENV["SURFER_URL"].to_s.empty? && !ENV["SURFER_TOKEN"].to_s.empty?
  end

  # Nahraje lokální soubor `path` na Surfer pod jeho basename (+ SURFER_REMOTE_DIR).
  # `logger` je volitelný callable (např. method(:log)); jinak tiše.
  def upload(path, logger: nil)
    say = ->(m) { logger&.call(m) }
    unless configured?
      say.call("  ℹ️  SURFER_URL/SURFER_TOKEN nenastaveny → upload přeskočen (#{path})")
      return :skipped
    end

    base  = ENV["SURFER_URL"].to_s.chomp("/")
    token = ENV["SURFER_TOKEN"].to_s
    dir   = ENV["SURFER_REMOTE_DIR"].to_s.gsub(%r{\A/+|/+\z}, "")
    remote = dir.empty? ? File.basename(path) : "#{dir}/#{File.basename(path)}"
    remote_enc = remote.split("/").map { |s| URI.encode_www_form_component(s) }.join("/")

    uri = URI("#{base}/api/files/#{remote_enc}" \
              "?access_token=#{URI.encode_www_form_component(token)}" \
              "&newFilePath=#{URI.encode_www_form_component(remote)}")

    boundary = "----MastoKatalog#{rand(10**16)}"
    body = +""
    body << "--#{boundary}\r\n"
    body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{File.basename(path)}\"\r\n"
    body << "Content-Type: application/octet-stream\r\n\r\n"
    body << File.binread(path)
    body << "\r\n--#{boundary}--\r\n"

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    req["User-Agent"] = "mastokatalog-upload/1.0"
    req.body = body

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 15
    http.read_timeout = 60
    resp = http.request(req)
    ok = resp.code.to_i.between?(200, 299)
    say.call("  #{ok ? '✅' : '❌'} upload → #{base}/#{remote} (HTTP #{resp.code})")
    ok ? :ok : :failed
  rescue StandardError => e
    say.call("  ❌ upload selhal: #{e.class}: #{e.message}")
    :failed
  end
end

CatalogConfig.load
