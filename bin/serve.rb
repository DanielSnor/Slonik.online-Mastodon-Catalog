#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimální statický HTTP server (stdlib socket) pro lokální náhled webu.
# Spuštění:  ruby bin/serve.rb [port] [dir]   (default dir = web/)
require "socket"

PORT = (ARGV[0] || "8765").to_i
ROOT = File.expand_path(ARGV[1] || File.join(__dir__, "..", "web"))

MIME = {
  ".html" => "text/html; charset=utf-8",
  ".js" => "application/javascript; charset=utf-8",
  ".css" => "text/css; charset=utf-8",
  ".json" => "application/json; charset=utf-8",
  ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg",
  ".png" => "image/png", ".svg" => "image/svg+xml",
  ".ico" => "image/x-icon",
}.freeze

server = TCPServer.new("127.0.0.1", PORT)
puts "Serving #{ROOT} on http://127.0.0.1:#{PORT}/  (Ctrl-C to stop)"

loop do
  client = server.accept
  begin
    request = client.gets
    next unless request

    path = request.split(" ")[1] || "/"
    path = path.split("?").first
    path = "/index.html" if path == "/"
    file = File.join(ROOT, path.gsub(/\.\./, ""))

    if File.file?(file)
      body = File.binread(file)
      ext = File.extname(file)
      ctype = MIME[ext] || "application/octet-stream"
      client.write("HTTP/1.1 200 OK\r\nContent-Type: #{ctype}\r\n" \
                   "Content-Length: #{body.bytesize}\r\nAccess-Control-Allow-Origin: *\r\n\r\n")
      client.write(body)
    else
      msg = "404 Not Found: #{path}"
      client.write("HTTP/1.1 404 Not Found\r\nContent-Type: text/plain; charset=utf-8\r\n" \
                   "Content-Length: #{msg.bytesize}\r\n\r\n#{msg}")
    end
  rescue StandardError => e
    warn "err: #{e.class}: #{e.message}"
  ensure
    client.close
  end
end
