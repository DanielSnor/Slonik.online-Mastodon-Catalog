# frozen_string_literal: true

# lib/ai.rb — sdílená AI kategorizace (Claude API) pro katalog.
#
# Jeden zdroj pravdy pro: SYSTEM_PROMPT, build_prompt, call_claude (s prompt
# cachingem), parse_ai_json, normalizaci výstupu a mapování rodin.
# Používají: update_catalog.rb (kategorizace účtů) i classify_instances.rb (zaměření instancí).
#
# Konfigurace přes ENV:
#   ANTHROPIC_API_KEY (povinné pro volání), AI_MODEL (default sonnet-4-5)
#
#   require_relative "lib/ai"
#   ai = AI.new(logger: method(:log))
#   res = ai.categorize(account_hash, statuses)   # → hash nebo { error: }

require "net/http"
require "json"
require "uri"
require_relative "mastodon_api"

class AI
  ANTHROPIC_URL     = "https://api.anthropic.com/v1/messages"
  ANTHROPIC_VERSION = "2023-06-01"
  MAX_TOKENS        = 400

  # Platné PoC rodiny (výstup modelu).
  FAMILIES = %w[news politics sport tech culture nature fun local other].freeze

  # PoC rodina → rodina produkčního katalogu (zdroj pravdy pro celý projekt).
  # POZOR: každá rodina z FAMILIES sem MUSÍ patřit — chybějící klíč spadne na
  # "lifestyle" (viz map_family), takže by se tiše slil s košem „other".
  FAMILY_MAP = {
    "news" => "news", "politics" => "government", "sport" => "sport",
    "tech" => "science_tech", "culture" => "culture", "nature" => "nature",
    "fun" => "humor", "local" => "local", "other" => "lifestyle",
  }.freeze
  VALID_CATALOG_FAMILIES = %w[news sport culture science_tech nature humor government local lifestyle].freeze

  # Pojistka proti tichému slití rodiny do „lifestyle": kdyby někdo přidal rodinu
  # do FAMILIES (nebo do SYSTEM_PROMPTu) a zapomněl na mapování, spadne to hned
  # při načtení, ne až po tisícovce zaplacených klasifikací.
  missing = FAMILIES - FAMILY_MAP.keys
  raise "FAMILY_MAP nemá mapování pro: #{missing.join(', ')}" unless missing.empty?

  unmapped = FAMILY_MAP.values.uniq - VALID_CATALOG_FAMILIES
  raise "FAMILY_MAP mapuje na neznámé rodiny: #{unmapped.join(', ')}" unless unmapped.empty?

  # Typ účtu (pole "type") — hodnoty se shodují s filtrem na frontendu.
  VALID_TYPES = %w[person team institution media other].freeze
  DEFAULT_TYPE = "person"

  # Statický system prompt — drží se nad minimem pro prompt caching (2 042 tokenů
  # měřeno přes /v1/messages/count_tokens 2. 8. 2026). Minimum je závislé na
  # modelu: 1 024 tokenů u Sonnetu 4.5/5, ale 4 096 u Haiku 4.5 — přechod na
  # menší model by caching tiše vypnul. Obsahuje definice rodin a few-shot
  # příklady (zlepšují trefování sport/local/nature).
  SYSTEM_PROMPT = <<~SYS
    Jsi klasifikátor profilů pro katalog českých a slovenských uživatelů sítě Mastodon.
    Pro každý profil dostaneš bio, pole profilu a posledních několik příspěvků.
    Tvým úkolem je profil zařadit do jedné rodiny, navrhnout tagy a napsat krátkou
    charakteristiku. Odpovídáš VÝHRADNĚ strojově čitelným JSON objektem.

    ## 1) RODINA — vyber právě jednu (pole "family")

    Zvol podle PŘEVAŽUJÍCÍHO tématu účtu, ne podle profese autora. Když člověk pracuje
    v IT, ale účet je hlavně o cyklistice, rodina je "sport", ne "tech".

    - news     = zpravodajství, aktuální dění, sdílení a komentování zpráv, novinařina
    - politics = politika, veřejné dění, aktivismus, volby, státní správa, EU, geopolitika
    - sport    = sport obecně i konkrétní odvětví: cyklistika, běh, fotbal, hokej,
                 turistika, fitness, vodáctví, lezení, jakákoli pohybová aktivita
    - tech     = technologie, IT, software, programování, hardware, kyberbezpečnost,
                 self-hosting, open source, gadgety, AI/ML
    - culture  = kultura a umění: literatura, film, hudba, divadlo, výtvarné umění,
                 fotografie jako tvorba, design, historie, jazyky, knihy
    - nature   = příroda, ekologie, počasí, zahradničení, biologie, zvířata, ochrana
                 přírody, klima jako přírodní (ne politické) téma
    - fun      = humor, zábava, satira, memy, odlehčený obsah, vtipné komentáře
    - local    = lokální komunita a regiony: dění v konkrétním městě/kraji, místní
                 spolky, sousedské info, regionální akce (Brno, Ostrava, Praha…)
    - other    = nelze spolehlivě zařadit do žádné z výše uvedených

    Rodiny "sport", "local" a "nature" se často přehlížejí — pokud jim účet tematicky
    odpovídá, použij je; nesypej takový obsah automaticky do "tech" nebo "culture".

    ## 2) TAGY — pole "tags", maximálně 5

    Volné tagy v angličtině, lowercase, mezery nahraď podtržítkem (např. "software_developer",
    "mountain_biking", "local_politics"). Popisují témata nebo profesi. Preferuj obecnější,
    znovupoužitelné tagy před jednorázovými. Příklady: journalist, software_developer,
    cycling, photography, feminism, local_politics, academic, gardening, open_source.

    ## 3) CHARAKTERISTIKA — pole "description"

    1–2 věty česky popisující, kdo daný účet je a co sdílí. Slouží jako ladicí pomůcka.

    ## 4) TYP ÚČTU — pole "type", vyber právě jeden

    Většina účtů jsou JEDNOTLIVCI → "person". Jiný typ zvol jen tehdy, když to bio
    nebo jméno jasně naznačuje. Při pochybnostech vol "person".

    - person      = konkrétní člověk / jednotlivec (i když píše o sobě v 1. osobě,
                    sdílí osobní obsah, je profesionál v oboru)
    - team        = kolektiv či skupina lidí bez formální právní struktury (parta,
                    projekt více lidí, "jsme", "tvoříme společně", redakční kolektiv bez média)
    - institution = formální organizace: spolek, z.s., firma, úřad, ministerstvo,
                    univerzita, knihovna, nezisková organizace, oficiální profil instituce
    - media       = médium / publikace: redakce, magazín, zpravodajský web/portál,
                    časopis, deník, značkový podcast (jako značka, ne osobní účet novináře)
    - other       = nic z výše uvedeného / nelze určit

    Pozn.: novinář jako osoba = "person"; magazín/redakce jako značka = "media".
    Člen nějakého spolku (osoba) = "person"; oficiální účet toho spolku = "institution".

    ## Příklady správného zařazení

    Tyto příklady ukazují očekávané uvažování a formát. Řiď se jimi, ale rozhoduj
    vždy podle skutečného obsahu konkrétního profilu.

    Profil: vývojář, sdílí převážně fotky z výletů na kole, závody, kilometry.
    → {"type": "person", "family": "sport", "tags": ["cycling", "software_developer", "outdoor", "racing"],
       "description": "Vývojář, jehož účet je hlavně o cyklistice — sdílí výlety, závody a najeté kilometry."}

    Profil: účet o dění v Ostravě, místní akce, doprava, tipy pro obyvatele.
    → {"type": "person", "family": "local", "tags": ["ostrava", "local_community", "city_life", "events"],
       "description": "Účet věnovaný dění v Ostravě — místní akce, doprava a tipy pro obyvatele."}

    Profil: zahradničení, ptáci na krmítku, počasí, sezónní práce na zahradě.
    → {"type": "person", "family": "nature", "tags": ["gardening", "birds", "weather", "seasons"],
       "description": "Sdílí radosti ze zahrady, pozorování ptáků a sezónní práce."}

    Profil: programátor, Linux, self-hosting, open source nástroje, kyberbezpečnost.
    → {"type": "person", "family": "tech", "tags": ["software_developer", "linux", "self_hosting", "open_source", "cybersecurity"],
       "description": "Programátor se zájmem o Linux, self-hosting a open source; sdílí technické postřehy."}

    Profil: oficiální profil státního úřadu, informuje o své agendě a novinkách.
    → {"type": "institution", "family": "politics", "tags": ["government", "public_administration", "official"],
       "description": "Oficiální účet státního úřadu informující o své agendě."}

    Profil: internetový magazín, několik redaktorů, recenze a články k jednomu tématu.
    → {"type": "media", "family": "tech", "tags": ["magazine", "reviews", "technology"],
       "description": "Internetový magazín s několika redaktory zaměřený na technologie."}

    Profil: „jsme parta nadšenců", společně pořádáme akce a tvoříme komunitní projekt.
    → {"type": "team", "family": "culture", "tags": ["collective", "community", "events"],
       "description": "Kolektiv nadšenců, který společně pořádá akce a tvoří komunitní projekt."}

    Profil: vtipné komentáře, memy, ironie k běžnému životu i k aktualitám.
    → {"type": "person", "family": "fun", "tags": ["humor", "memes", "satire", "internet_culture"],
       "description": "Odlehčený účet plný vtipných komentářů, memů a ironie."}

    ## Výstupní formát

    Odpověz POUZE jedním JSON objektem, bez markdown bloků, bez komentářů, bez textu navíc:
    {"type": "...", "family": "...", "tags": ["...", "..."], "description": "..."}
  SYS

  # Pojistka na few-shot příklady: dřív dva z nich ukazovaly rodiny "government"
  # a "science_tech", což jsou názvy rodin KATALOGU, ne platné hodnoty z FAMILIES.
  # Model je občas napodobil, normalize je srazil na "other" a účet spadl do koše
  # „lifestyle" — tiše, bez chyby. Tohle to nechá spadnout hned při načtení.
  example_families = SYSTEM_PROMPT.scan(/"family":\s*"([^"]+)"/).flatten
                                  .reject { |f| f == "..." }.uniq
  bad_examples = example_families - FAMILIES
  unless bad_examples.empty?
    raise "SYSTEM_PROMPT ukazuje neplatné rodiny: #{bad_examples.join(', ')} " \
          "(platné jsou #{FAMILIES.join('/')}; rodiny katalogu sem nepatří)"
  end

  def initialize(logger: nil, model: nil, api_key: nil)
    @log = logger || ->(_m) {}
    @model = model || ENV["AI_MODEL"] || "claude-sonnet-4-5-20250929"
    @api_key = api_key || ENV["ANTHROPIC_API_KEY"]
  end

  attr_reader :model

  def map_family(poc_family)
    FAMILY_MAP[poc_family.to_s.downcase.strip] || "lifestyle"
  end

  # Postaví user prompt z účtu (lookup objekt) + jeho statusů. Jen variabilní
  # data — instrukce jsou v SYSTEM_PROMPT (cachovaná část).
  def build_prompt(acct, statuses)
    bio = MastodonAPI.strip_html(acct["note"])
    bio = "(prázdné)" if bio.empty?
    fields = (acct["fields"] || [])
             .map { |f| "#{MastodonAPI.strip_html(f['name'])}: #{MastodonAPI.strip_html(f['value'])}" }
             .join("\n")
    fields = "(žádná)" if fields.empty?
    posts = statuses.each_with_index.map do |s, i|
      t = MastodonAPI.strip_html(s["content"])
      t = "(bez textu / jen média)" if t.empty?
      "#{i + 1}. [#{s['language'] || '?'}] #{t}"
    end.join("\n")
    posts = "(žádné příspěvky)" if posts.strip.empty?
    dom = MastodonAPI.dominant_language(statuses) || "neznámý"

    <<~PROMPT
      Zařaď tento Mastodon profil.

      BIO:
      #{bio}

      POLE PROFILU:
      #{fields}

      POSLEDNÍCH #{statuses.size} PŘÍSPĚVKŮ (od nejnovějšího):
      #{posts}

      JAZYK PŘÍSPĚVKŮ (nejčastější): #{dom}
    PROMPT
  end

  # Zavolá Claude. Vrací hash: { text:, stop_reason:, prompt_tokens:,
  # response_tokens:, cache_creation_tokens:, cache_read_tokens: } nebo { error: }.
  # stop_reason == "max_tokens" znamená useknutou odpověď — volající to musí
  # odlišit od rozbitého JSONu, jinak vypadá plný strop jako chyba modelu.
  # system: volitelný vlastní system prompt (default = SYSTEM_PROMPT pro účty);
  # předej statický řetězec >1024 tokenů, ať funguje prompt caching.
  def call(prompt, attempt: 1, system: SYSTEM_PROMPT)
    uri = URI(ANTHROPIC_URL)
    req = Net::HTTP::Post.new(uri)
    req["x-api-key"] = @api_key
    req["anthropic-version"] = ANTHROPIC_VERSION
    req["content-type"] = "application/json"
    req.body = JSON.generate(
      model: @model, max_tokens: MAX_TOKENS,
      system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
      messages: [{ role: "user", content: prompt }],
    )
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 60
    resp = http.request(req)
    code = resp.code.to_i
    if code == 200
      j = JSON.parse(resp.body)
      { text: j.dig("content", 0, "text").to_s,
        stop_reason: j["stop_reason"],
        prompt_tokens: j.dig("usage", "input_tokens"),
        response_tokens: j.dig("usage", "output_tokens"),
        cache_creation_tokens: j.dig("usage", "cache_creation_input_tokens"),
        cache_read_tokens: j.dig("usage", "cache_read_input_tokens") }
    elsif [429, 500, 502, 503, 529].include?(code) && attempt <= 3
      sleep(2**attempt)
      call(prompt, attempt: attempt + 1, system: system)
    else
      { error: "api_error_#{code}", detail: resp.body.to_s[0, 200] }
    end
  rescue StandardError => e
    if attempt <= 3
      sleep(2**attempt)
      call(prompt, attempt: attempt + 1, system: system)
    else
      { error: "exception", detail: "#{e.class}: #{e.message}" }
    end
  end

  # Robustní extrakce JSON objektu z odpovědi modelu.
  def parse_json(text)
    cleaned = text.to_s.strip.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
    s = cleaned.index("{")
    e = cleaned.rindex("}")
    return nil if s.nil? || e.nil? || e < s

    JSON.parse(cleaned[s..e])
  rescue JSON::ParserError
    nil
  end

  # Normalizuje parsed odpověď na PoC tvar (family/tags/description + meta).
  def normalize(parsed, usage = {})
    fam = parsed["family"].to_s.downcase.strip
    fam = "other" unless FAMILIES.include?(fam)
    type = parsed["type"].to_s.downcase.strip
    type = DEFAULT_TYPE unless VALID_TYPES.include?(type)
    tags = Array(parsed["tags"]).map { |t| t.to_s.downcase.strip.gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, "") }
                                .reject(&:empty?).uniq.first(5)
    {
      "type" => type,
      "family" => fam,
      "tags" => tags,
      "description" => parsed["description"].to_s.strip,
      "model" => @model,
      "prompt_tokens" => usage[:prompt_tokens],
      "response_tokens" => usage[:response_tokens],
      "cache_creation_tokens" => usage[:cache_creation_tokens],
      "cache_read_tokens" => usage[:cache_read_tokens],
    }
  end
end
