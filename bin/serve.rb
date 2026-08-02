#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimální statický HTTP server (stdlib socket) pro lokální náhled webu.
# Spuštění:  ruby bin/serve.rb [port] [dir]   (default dir = web/)
require "socket"
require "uri"

PORT = (ARGV[0] || "8765").to_i
ROOT = File.expand_path(ARGV[1] || File.join(__dir__, "..", "web"))

MIME = {
  ".html" => "text/html; charset=utf-8",
  ".js" => "application/javascript; charset=utf-8",
  ".css" => "text/css; charset=utf-8",
  ".json" => "application/json; charset=utf-8",
  ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg",
  ".png" => "image/png", ".svg" => "image/svg+xml",
  ".webp" => "image/webp", ".gif" => "image/gif",
  ".ico" => "image/x-icon",
}.freeze

server = TCPServer.new("127.0.0.1", PORT)
puts "Serving #{ROOT} on http://127.0.0.1:#{PORT}/  (Ctrl-C to stop)"

# Převede cestu z requestu na soubor uvnitř ROOT, nebo nil.
#
# Dřív se „..“ jen vymazávalo ze stringu (`gsub(/\.\./, "")`), což je filtr, ne
# kontrola — nezahrnoval procentové kódování a u vstupu jako `/....//x` mazání
# samo složí platné `../`. Správně je cestu dekódovat, složit a teprve na
# VÝSLEDKU ověřit, že leží pod kořenem.
def resolve(path)
  path = path.split("?").first.to_s
  path = URI::DEFAULT_PARSER.unescape(path)
  return nil if path.empty? || path.include?("\0")

  path = "/index.html" if path == "/"
  file = File.expand_path(File.join(ROOT, path))
  return nil unless file == ROOT || file.start_with?(ROOT + File::SEPARATOR)

  file
end

loop do
  client = server.accept
  begin
    request = client.gets
    next unless request

    file = resolve(request.split(" ")[1] || "/")

    if file && File.file?(file)
      body = File.binread(file)
      ext = File.extname(file)
      ctype = MIME[ext] || "application/octet-stream"
      client.write("HTTP/1.1 200 OK\r\nContent-Type: #{ctype}\r\n" \
                   "Content-Length: #{body.bytesize}\r\nAccess-Control-Allow-Origin: *\r\n\r\n")
      client.write(body)
    else
      # Cestu z requestu do odpovědi nevracíme — nemá smysl a je to zbytečná
      # plocha na reflektovaný obsah.
      msg = "404 Not Found"
      client.write("HTTP/1.1 404 Not Found\r\nContent-Type: text/plain; charset=utf-8\r\n" \
                   "Content-Length: #{msg.bytesize}\r\n\r\n#{msg}")
    end
  rescue StandardError => e
    warn "err: #{e.class}: #{e.message}"
  ensure
    client.close
  end
end
