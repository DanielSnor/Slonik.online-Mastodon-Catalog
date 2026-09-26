#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# test_surfer.rb — ověření přístupu na Surfer (Cloudron) přes jeho Files API.
#
# Surfer NEpoužívá WebDAV. Upload je:
#   POST /api/files/<remote>   (přihlášení jako lib/config.rb: heslo, jinak token)
#   Content-Type: multipart/form-data, pole "file". Úspěch = HTTP 201.
#
# Test:
#   1. POST nahraje testovací soubor (mastokatalog_test.txt)
#   2. GET  ověří, že je veřejně dostupný a obsah sedí
#   3. DELETE uklidí (Surfer Files API: DELETE /api/files/<remote>)
#
# Spuštění:
#   ruby test_surfer.rb
#   ruby test_surfer.rb --keep     # nemazat testovací soubor
#
# Credentials z config.env (SURFER_URL, SURFER_USERNAME + SURFER_PASSWORD nebo
# SURFER_TOKEN, SURFER_REMOTE_DIR).
# =============================================================================

require "net/http"
require "uri"
require_relative "../lib/config"

KEEP = ARGV.include?("--keep")
TEST_NAME = "mastokatalog_test.txt"
TEST_BODY = "MastoKatalog Surfer test #{Time.now.utc.iso8601}\n"

def die(msg)
  warn "❌ #{msg}"
  exit 1
end

base  = ENV["SURFER_URL"].to_s.chomp("/")
die("SURFER_URL není nastaven. Vyplň config.env.") if base.empty?
die("Chybí přihlášení: SURFER_USERNAME + SURFER_PASSWORD (Surfer 7) nebo SURFER_TOKEN. Vyplň config.env.") unless Surfer.configured?

remote = Surfer.remote_path(TEST_NAME)
remote_enc = Surfer.encode_remote(remote)
api = Surfer.api_uri(remote, "newFilePath" => remote)
public_url = URI("#{base}/#{remote_enc}")

puts "Surfer:       #{base}"
puts "Přihlášení:   #{Surfer.password? ? "heslo (#{ENV["SURFER_USERNAME"]})" : 'token'}"
puts "Cílový soubor: /#{remote}"
puts "Veřejná URL:  #{public_url}"
puts "------------------------------------------------------------"

def http_for(uri)
  h = Net::HTTP.new(uri.host, uri.port)
  h.use_ssl = (uri.scheme == "https")
  h.open_timeout = 15
  h.read_timeout = 60
  h
end

# --- 1) POST (multipart) ---
boundary = "----MastoKatalog#{rand(10**16)}"
body = +""
body << "--#{boundary}\r\n"
body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{TEST_NAME}\"\r\n"
body << "Content-Type: text/plain\r\n\r\n"
body << TEST_BODY
body << "\r\n--#{boundary}--\r\n"

post = Surfer.authorize(Net::HTTP::Post.new(api))
post["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
post["User-Agent"] = "mastokatalog-test/1.0"
post.body = body
begin
  resp = http_for(api).request(post)
rescue StandardError => e
  die("POST spojení selhalo: #{e.class}: #{e.message}\n   (Zkontroluj SURFER_URL, síť, TLS.)")
end
code = resp.code.to_i
puts "1) POST → HTTP #{resp.code}"
if code == 401 || code == 403
  die("#{code} — Surfer odmítl přihlášení (#{Surfer.password? ? 'SURFER_USERNAME/SURFER_PASSWORD' : 'SURFER_TOKEN -- Surfer 7 tokeny nebere'}) nebo chybí práva.")
elsif code == 400
  die("400 — Surfer odmítl požadavek: #{resp.body.to_s[0, 160]}")
elsif code == 404
  die("404 — špatná API cesta. Čekám /api/files/… na SURFER_URL. Tělo: #{resp.body.to_s[0, 120]}")
elsif !code.between?(200, 299)
  die("Neočekávaný kód #{resp.code}. Tělo: #{resp.body.to_s[0, 160]}")
end
puts "   ✅ zápis OK (HTTP #{resp.code})"

# --- 2) GET veřejné URL ---
resp = http_for(public_url).request(Net::HTTP::Get.new(public_url))
puts "2) GET  → HTTP #{resp.code}  (#{public_url})"
if resp.code.to_i.between?(200, 299) && resp.body.to_s.include?("MastoKatalog Surfer test")
  puts "   ✅ čtení OK (soubor je veřejně dostupný, obsah sedí)"
else
  puts "   ⚠️  zápis prošel, ale veřejné čtení neověřeno (HTTP #{resp.code}) — zkontroluj cestu/REMOTE_DIR"
end

# --- 3) DELETE úklid ---
if KEEP
  puts "3) DELETE přeskočeno (--keep). Soubor zůstává: #{public_url}"
else
  del = Surfer.authorize(Net::HTTP::Delete.new(Surfer.api_uri(remote)))
  del["User-Agent"] = "mastokatalog-test/1.0"
  begin
    resp = http_for(api).request(del)
    if resp.code.to_i.between?(200, 299)
      puts "3) DELETE → HTTP #{resp.code}  ✅ úklid OK"
    else
      puts "3) DELETE → HTTP #{resp.code}  ⚠️  nešlo smazat — smaž ručně přes Surfer"
    end
  rescue StandardError => e
    puts "3) DELETE selhalo: #{e.class} — smaž ručně"
  end
end

puts "------------------------------------------------------------"
puts "✅ Surfer Files API funguje. consolidate_posts.rb / update_catalog bude moci uploadovat."
