# frozen_string_literal: true

# lib/mastodon_api.rb — sdílená vrstva pro veřejné Mastodon API.
#
# Jeden zdroj pravdy pro: HTTP GET (s per-instance rate limit awareness),
# lookup účtu, stažení statusů, strip HTML, detekci dominantního jazyka.
#
# Konfigurace přes ENV (nastaví je lib/config z config.env):
#   MASTODON_TOKEN        read-only bearer token (volitelný)
#   MASTODON_DELAY        sekundy mezi requesty (default 1.0)
#   RATE_REMAINING_FLOOR  práh X-RateLimit-Remaining, pod kterým čekáme (default 10)
#
# Použití:
#   require_relative "lib/mastodon_api"
#   api = MastodonAPI.new(logger: method(:log))
#   acct = api.lookup("witter.cz", "tomucha")
#   posts = api.statuses("witter.cz", acct["id"], limit: 20)

require "net/http"
require "json"
require "uri"
require "time"

class MastodonAPI
  USER_AGENT = "mastokatalog/1.0 (+https://katalog-test.zpravobot.news; research)"

  def initialize(logger: nil, delay: nil, token: nil)
    @log = logger || ->(_m) {}
    @delay = (delay || ENV["MASTODON_DELAY"] || "1.0").to_f
    @token = token || ENV["MASTODON_TOKEN"]
    @floor = (ENV["RATE_REMAINING_FLOOR"] || "10").to_i
    @rate = {} # host => { remaining:, reset_at: }
  end

  # Vrátí [http_code, parsed_json_or_nil, link_header]. Nehází výjimky.
  def get(host, path)
    respect_rate_limit(host)
    base, query = path.split("?", 2)
    uri = URI::HTTPS.build(host: host, path: base, query: query)
    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = USER_AGENT
    req["Accept"] = "application/json"
    req["Authorization"] = "Bearer #{@token}" if @token

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 25
    resp = http.request(req)

    record_rate(host, resp)

    code = resp.code.to_i
    if code == 429
      retry_after = resp["retry-after"].to_i
      retry_after = 30 if retry_after <= 0
      @log.call("  ⚠️  429 #{host}, čekám #{retry_after}s a opakuji")
      sleep(retry_after)
      return get(host, path)
    end

    sleep(@delay) if @delay.positive?
    parsed = (JSON.parse(resp.body) if code == 200 && resp["content-type"].to_s.include?("json"))
    [code, parsed, resp["link"]]
  rescue StandardError => e
    @log.call("  ⚠️  GET #{host}#{path} → #{e.class}: #{e.message}")
    [0, nil, nil]
  end

  # Zjednodušené: vrací jen parsed JSON (nebo nil).
  def get_json(host, path)
    get(host, path)[1]
  end

  def lookup(host, username)
    get_json(host, "/api/v1/accounts/lookup?acct=#{URI.encode_www_form_component(username)}")
  end

  # Stáhne statusy účtu. exclude_replies/reblogs a min_id konfigurovatelné.
  def statuses(host, account_id, limit: 40, exclude_replies: false, exclude_reblogs: true, min_id: nil)
    q = "limit=#{limit}&exclude_reblogs=#{exclude_reblogs}"
    q += "&exclude_replies=true" if exclude_replies
    q += "&min_id=#{min_id}" if min_id
    arr = get_json(host, "/api/v1/accounts/#{account_id}/statuses?#{q}")
    arr.is_a?(Array) ? arr : []
  end

  # Vyparsuje max_id z Link hlavičky (rel="next") pro stránkování.
  def self.next_max_id(link_header)
    return nil if link_header.nil?

    m = link_header.match(/max_id=(\d+)[^>]*>\s*;\s*rel="next"/)
    m && m[1]
  end

  # ---- statické text utility (bez stavu) ----

  # Odstraní HTML. Inline tagy BEZ mezery (Mastodon obaluje hashtagy/URL do spanů),
  # blokové (</p>, <br>) → zalomení. Dekóduje základní entity.
  def self.strip_html(html)
    return "" if html.nil?

    text = html.gsub(%r{</p>}i, "\n\n").gsub(%r{<br\s*/?>}i, "\n").gsub(/<[^>]+>/, "")
    text.gsub("&amp;", "&").gsub("&lt;", "<").gsub("&gt;", ">")
        .gsub("&quot;", '"').gsub("&#39;", "'").gsub(/&nbsp;/i, " ")
        .gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip
  end

  # Nejčastější jazyk ze statusů (cs/sk/en/…) nebo nil.
  def self.dominant_language(statuses)
    langs = statuses.map { |s| s["language"] }.compact.reject(&:empty?)
    return nil if langs.empty?

    langs.tally.max_by { |_, n| n }.first
  end

  private

  def record_rate(host, resp)
    return unless resp["x-ratelimit-remaining"]

    @rate[host] = {
      remaining: resp["x-ratelimit-remaining"].to_i,
      reset_at: (Time.parse(resp["x-ratelimit-reset"]) rescue nil),
    }
  end

  def respect_rate_limit(host)
    st = @rate[host]
    return unless st && st[:remaining] && st[:remaining] <= @floor && st[:reset_at]

    wait = st[:reset_at] - Time.now
    return unless wait.positive?

    @log.call("  ⏳ #{host}: zbývá #{st[:remaining]} req, čekám #{wait.ceil}s do resetu okna")
    sleep(wait + 0.5)
    @rate[host] = nil
  end
end
