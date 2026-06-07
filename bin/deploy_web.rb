#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# bin/deploy_web.rb — nahraje web bundle (web/) na Surfer.
#
# Používá STEJNÝ způsob jako upload JSON v aplikaci: Surfer.upload z lib/config
# (Files API: POST /api/files/<name>?access_token=…&newFilePath=<name>, multipart).
# Spouští se na TEST serveru (kde je config.env se SURFER_URL/SURFER_TOKEN).
#
# Použití:
#   ruby bin/deploy_web.rb            # celý bundle (frontend + data.json + posts.json)
#   ruby bin/deploy_web.rb --assets   # jen frontend (index.html, app.js, app.css, header.jpg)
#   ruby bin/deploy_web.rb --data     # jen data.json + posts.json
#   ruby bin/deploy_web.rb --dry-run  # jen vypíše, co by nahrál (nevyžaduje Surfer)
#
# ENV: SURFER_URL, SURFER_TOKEN, SURFER_REMOTE_DIR (viz config.env).
# =============================================================================

require_relative "../lib/config"

DRY = ARGV.include?("--dry-run")
ASSETS = %w[index.html app.js app.css links.js header.jpg slonik.png oscloud.png daniel.jpg qr.jpg
            card-instance.png card-account.png card-account-detail.png card-post.png search-results.png].freeze
DATA   = %w[data.json posts.json search.json users.json instances.json status.json].freeze

files =
  if    ARGV.include?("--assets") then ASSETS
  elsif ARGV.include?("--data")   then DATA
  else ASSETS + DATA
  end

def log(msg)
  puts msg
  $stdout.flush
end

unless DRY || Surfer.configured?
  abort("❌ Surfer není nakonfigurován (SURFER_URL/SURFER_TOKEN v config.env)")
end

dir = ENV["SURFER_REMOTE_DIR"].to_s
target = ENV["SURFER_URL"].to_s.chomp("/") + (dir.empty? ? "" : "/#{dir}")
log("Deploy web → Surfer: #{target}#{DRY ? '  [DRY-RUN]' : ''}")

ok = failed = skipped = 0
files.each do |name|
  path = File.join(Paths::WEB_DIR, name)
  unless File.exist?(path)
    log("  ⚠️  #{name}: v web/ neexistuje — přeskočeno")
    skipped += 1
    next
  end
  if DRY
    log("  [dry] #{name} (#{File.size(path)} B)")
    next
  end
  case Surfer.upload(path, logger: method(:log))
  when :ok then ok += 1
  else failed += 1
  end
end

unless DRY
  log("")
  log("Hotovo: nahráno #{ok}, chyb #{failed}, přeskočeno #{skipped}")
  exit(failed.zero? ? 0 : 1)
end
