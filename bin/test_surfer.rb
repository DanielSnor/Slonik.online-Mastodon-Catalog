#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# test_surfer.rb — ověření přístupu na Surfer (Cloudron) přes jeho Files API.
#
# Surfer NEpoužívá WebDAV. Upload je:
#   POST /api/files/<remote>?access_token=TOKEN&newFilePath=<remote>
#   Content-Type: multipart/form-data, pole "file". Úspěch = HTTP 201.
#
# Test:
#   1. POST nahraje testovací soubor (mastokatalog_test.txt)
#   2. GET  ověří, že je veřejně dostupný a obsah sedí
#   3. DELETE uklidí (Surfer Files API: DELETE /api/files/<remote>?access_token=…)
#
# Spuštění:
#   ruby test_surfer.rb
#   ruby test_surfer.rb --keep     # nemazat testovací soubor
#
# Credentials z config.env (SURFER_URL / SURFER_TOKEN / SURFER_REMOTE_DIR).
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
token = ENV["SURFER_TOKEN"].to_s
die("SURFER_URL není nastaven. Vyplň config.env.") if base.empty?
die("SURFER_TOKEN není nastaven. Vyplň config.env (Surfer access_token).") if token.empty?

remote_dir = ENV["SURFER_REMOTE_DIR"].to_s.gsub(%r{\A/+|/+\z}, "")
remote = remote_dir.empty? ? TEST_NAME : "#{remote_dir}/#{TEST_NAME}"
remote_enc = remote.split("/").map { |s| URI.encode_www_form_component(s) }.join("/")

api = URI("#{base}/api/files/#{remote_enc}" \
          "?access_token=#{URI.encode_www_form_component(token)}" \
          "&newFilePath=#{URI.encode_www_form_component(remote)}")
public_url = URI("#{base}/#{remote_enc}")

puts "Surfer:       #{base}"
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

post = Net::HTTP::Post.new(api)
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
  die("#{code} — neplatný SURFER_TOKEN nebo chybějící práva.")
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
  del = Net::HTTP::Delete.new(URI("#{base}/api/files/#{remote_enc}?access_token=#{URI.encode_www_form_component(token)}"))
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
