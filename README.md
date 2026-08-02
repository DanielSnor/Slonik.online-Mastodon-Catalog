# MastoKatalog CZ/SK („Sloník")

Katalog českých a slovenských uživatelů Mastodonu + týdenní žebříčky postů.
Data se sbírají přes **veřejné Mastodon API**, kategorizují přes **Claude API** a
publikují jako statický web na **Surfer** (Cloudron) — `katalog-test.zpravobot.news`.

Vzniklo jako PoC průzkum (5 fází); historické artefakty jsou v `archiv/`.

## Stack

Čisté **Ruby, pouze stdlib** (`net/http`, `json`, `uri`, `time`, `set`, `date`).
Žádný Gemfile, žádný bundler, žádná DB. Testováno proti **Ruby 3.4**.

## Struktura repozitáře

```
bin/                    spustitelné skripty (entry points)
  discover_accounts.rb    objevování účtů ze sociálního grafu + directory
  update_catalog.rb       inkrementální aktualizace web/data.json (AI jen pro nové)
  collect_posts.rb        denní sběr postů → data/posts_YYYY_Www.jsonl
  consolidate_posts.rb    týdenní konsolidace → web/posts.json → upload na Surfer
  build_search.rb         přírůstkový index pro vyhledávání → web/search.json + users.json
  build_instances.rb      přehled instancí (v2/v1 /instance) → web/instances.json
  classify_instances.rb   zaměření instancí (joinmastodon + AI) → data/instance_topics.json
  deploy_web.rb           nahraje web bundle (web/) na Surfer (Files API)
  serve.rb                lokální statický HTTP server pro náhled (default web/)
  test_surfer.rb          ověření přístupu na Surfer (POST/GET/DELETE)

lib/                    sdílené knihovny (žádná duplicita logiky)
  paths.rb                kořenové kotvení cest (ROOT, CONFIG_DIR, DATA_DIR, WEB_DIR…)
  config.rb               loader config.env + read_list + Surfer.upload (Files API)
  mastodon_api.rb         MastodonAPI: HTTP, rate limit, lookup, statuses, strip_html…
  ai.rb                   AI: SYSTEM_PROMPT, typ/rodina/tagy, build_prompt/call/normalize

config/                 kurátorské seznamy + šablony (verzované)
  instances.txt           CZ/SK Mastodon instance (jedna doména/řádek)
  feeds.txt               „obsahové" instance (boti/zprávy) → search + posty, mimo katalog
  seeds.txt               seed účty pro discovery ("acct directions")
  manual_accounts.txt     ruční zařazení účtů (handle/řádek) — boty ap.
  blocklist.txt           ruční vyřazení účtů (handle/řádek) — odstranění
  crontab.example         cron (collect denně, search à 6 h; consolidate/discover/update/classify/instances pondělí)

data/                   data (vstupy/výstupy/stav; generované jsou v .gitignore)
  discovered_accounts.json  kandidáti z discovery
  skipped_noncz.json        cache vyřazených (ne-CZ/SK + boti)
  collect_state.json        min_id stav přírůstkového sběru
  search_state.json         poslední viděné status id per zdroj (přírůstkový search)
  instance_topics.json      cache zaměření instancí (host → kategorie; joinmastodon/AI)
  metrics_snapshot.json     předchozí followers/statuses účtů → týdenní přírůstky (Skokani v Účtech)
  posts_YYYY_Www.jsonl      denní sběr postů (do konsolidace)
  ai_results.json/.jsonl    výstup diagnostické kategorizace

web/                    nasaditelný web (index.html, app.js, app.css, header.jpg,
                        links.js = kurátorovaný rozcestník (tab Odkazy), data.json = katalog,
                        posts.json, DEPLOY.md; search.json + users.json = vyhledávání,
                        instances.json = tab Instance)
docs/                   dokumentace (ai_report.md…)
logs/                   logy běhů
scripts/                deploy: sync_local_to_test.sh, sync_test_to_prod.sh,
                        sync_data_to_test.sh + migrate_layout.sh (převod layoutu)
archiv/                 historické PoC artefakty
config.env.example      šablona konfigurace; reálný config.env (kořen) je v .gitignore
```

> ⚠️ Skripty potřebují **odchozí HTTPS** na cizí Mastodon instance. V sandboxu
> s TLS-interceptující proxy (falešné 404 / cert mismatch) sběr neproběhne.

## Rychlé spouštění (shell skripty v kořeni)

Tenké wrappery — samy přejdou do kořene projektu a `update.sh` načte
`ANTHROPIC_API_KEY` z `~/.anthropic_key`. Argumenty se propisují dál.

| Skript | Co dělá |
|---|---|
| `./serve.sh [port]` | lokální náhled webu (`web/`, default 8765) |
| `./discover.sh` | objevování účtů → `data/discovered_accounts.json` |
| `./update.sh [flagy]` | aktualizace katalogu (`--dry-run`, `--no-categorize`, `--retype`…) |
| `./update.sh --bg [flagy]` | totéž na pozadí → `logs/update.log` (+ `logs/update.pid`) |
| `./collect.sh` | denní sběr postů |
| `./consolidate.sh` | týdenní konsolidace postů |
| `./build-search.sh [--rebuild]` | index pro vyhledávání → `search.json` + `users.json` (přírůstkově; `--rebuild` = plný) |
| `./build-search.sh --bg [flagy]` | totéž na pozadí → `logs/search.log` (+ `logs/search.pid`) |
| `./build-instances.sh` | přehled instancí → `instances.json` |
| `./classify-instances.sh [--rebuild\|--dry-run]` | zaměření instancí (joinmastodon + AI) → cache |
| `./refresh-instances.sh` | build → classify → build v jednom (kategorie i pro nové instance) |
| `./deploy-web.sh [--assets\|--data]` | nahraje web bundle na Surfer (na serveru) |
| `./test-surfer.sh` | ověření přístupu na Surfer |

Pod kapotou volají `ruby bin/<skript>.rb`; jdou spouštět i přímo.

## Nasazení na server (deploy)

```bash
cp scripts/deploy.env.example scripts/deploy.env   # vyplň SSH souřadnice serveru
./scripts/sync_local_to_test.sh --dry-run          # náhled, co se nahraje
./scripts/sync_local_to_test.sh                    # nahraje KÓD (rsync přes SSH)
```

Synchronizuje **jen kód** (`bin/`, `lib/`, `*.sh`, `scripts/*.sh`, `web/` assety
**vč. obrázků** bez `*.json` dat, `docs/`, README). **Nikdy nepřepíše** `config.env`,
`data/`, `web/*.json`, `logs/` ani (defaultně) `config/*.txt`. Seznamy pošleš jen vědomě:
`./scripts/sync_local_to_test.sh --with-config`.

### Test ↔ Prod (na serveru)

Obě instance jsou na serveru (`/app/data/slonik-test` a `/app/data/slonik`); rsync
běží lokálně na serveru přes SSH. Nastav `SLONIK_PROD_DIR` v `scripts/deploy.env`.

```bash
./scripts/sync_test_to_prod.sh --dry-run    # promote KÓDU test → prod (náhled)
./scripts/sync_test_to_prod.sh              # bez data/, config.env, config/, web/*.json
./scripts/sync_test_to_prod.sh --with-config  # i config/ (seznamy + crontab)

./scripts/sync_data_to_test.sh --dry-run    # zrcadlení DAT prod → test (náhled)
./scripts/sync_data_to_test.sh              # jen data/ + web/*.json (test nad reálnými daty)
```

- **test → prod**: aplikace + web assety, **bez** dat a konfigurací (prod má vlastní).
- **data prod → test**: jen datové soubory (`data/` + `web/*.json`), kód/config beze změny.
- Žádný z nich nepoužívá `--delete`.

První přechod ze starého plochého layoutu na serveru: `scripts/migrate_layout.sh`
(viz jeho hlavička).

### Publikace webu na Surfer (test → Surfer)

Frontend (index.html/app.js/app.css/header.jpg) se na živý web nahrává **na serveru**
přes Files API — stejný `Surfer.upload` jako pro JSON:

```bash
# na test serveru (má config.env se SURFER_TOKEN):
./deploy-web.sh --dry-run     # náhled, co se nahraje
./deploy-web.sh --assets      # jen frontend (po změně app.js/css/html)
./deploy-web.sh               # celý bundle (frontend + data.json + posts.json)
```

`data.json`/`posts.json` se jinak publikují samy z `update_catalog`/`consolidate_posts`;
`deploy-web.sh --assets` použiješ po změně frontendu.

**Celý deploy řetězec:** lokálně edituješ → `sync_local_to_test.sh` (Mac → server) →
`deploy-web.sh` (server → Surfer).

## Konfigurace (`config.env`)

Credentials a nastavení se drží v `config.env` (mimo git). Skripty si ho načtou
samy přes `require_relative "../lib/config"`.

```bash
cp config.env.example config.env   # pak vyplň
chmod 600 config.env
```

- Formát `KEY=value`, jeden na řádek; hodnoty mohou být v uvozovkách.
- **Skutečné ENV proměnné mají přednost** — config jde kdykoli přebít
  (`MASTODON_DELAY=2 ruby bin/collect_posts.rb`).
- Cestu lze změnit přes `CONFIG_PATH`.
- `config.env` je v `.gitignore` (obsahuje tajemství). Šablona = `config.env.example`.

| Klíč | Význam |
|---|---|
| `SURFER_URL` | base URL Surferu (např. `https://katalog-test.zpravobot.news`) |
| `SURFER_TOKEN` | Surfer access_token (Files API) |
| `SURFER_REMOTE_DIR` | cílová podsložka na Surferu (prázdné = root) |
| `MASTODON_TOKEN` | read-only bearer token (volitelný; lepší rate limity) |
| `ANTHROPIC_API_KEY` | Claude API klíč (lépe přes ENV / `~/.anthropic_key`, ne do config.env) |
| `MASTODON_DELAY` | sekundy mezi Mastodon requesty |

> 🔐 **Nikdy** nevkládej tokeny do chatu/commitu. Při úniku rotuj. `ANTHROPIC_API_KEY`
> drž raději v `~/.anthropic_key` (`chmod 600`) a předávej přes ENV (riziko iCloud sync).
>
> Surfer (web) a tyto Ruby skripty + `config.env` běží na **oddělených serverech** —
> skripty a tajemství nejsou web-exposed.

## Surfer (upload)

Surfer **nepoužívá WebDAV**. Upload je přes jeho Files API:

```
POST /api/files/<remote>?access_token=TOKEN&newFilePath=<remote>
Content-Type: multipart/form-data, pole "file"   → úspěch HTTP 201
```

Sdílená implementace je `Surfer.upload(path, logger:)` v `lib/config.rb`
(používá `consolidate_posts.rb` i `update_catalog.rb`). Ověření: `ruby bin/test_surfer.rb`.

---

# Produkční pipeline

```
discover_accounts.rb  →  update_catalog.rb            (účty: rozšíř + dokategorizuj)
collect_posts.rb (denně)  →  consolidate_posts.rb (Po)  (posty: žebříčky)
```

## `discover_accounts.rb` — objevování účtů

Kandidáti se sbírají ze **dvou zdrojů** (slévají se + dedup):

1. **Sociální graf seedů** (`seeds.txt`) — `followers`/`following` seed účtů;
   reálné CZ/SK účty napříč libovolnými instancemi (i velkými, kde jsou Češi ~0,1 %).
2. **Lokální directory CZ/SK instancí** (`instances.txt`) — `/api/v1/directory`
   každé instance; zachytí i účty, které nikdo ze seed grafu nesleduje.

```bash
ruby bin/discover_accounts.rb        # → discovered_accounts.json
```

**Seznamy jsou v datových souborech (verzované, ne v kódu):**
- `seeds.txt` — řádky `username@instance  directions` (`followers` | `following` |
  `followers,following`). Override: `SEEDS_FILE`.
- `instances.txt` — jedna doména na řádek, `#` = komentář. Override: `INSTANCES_FILE`.
  Předvyplněno empiricky nalezenými CZ/SK instancemi; edituj volně (mrtvé/bez
  directory se jen přeskočí).

- Hloubka 1 úroveň, bez CZ/SK filtru (jen vyřadí boty + dedup); filtruje až kategorizace.
- Stránkování: graf přes `Link` hlavičku, directory přes `offset`. Funguje **bez tokenu**.
- ENV: `MASTODON_TOKEN`, `MASTODON_DELAY`, `MAX_PER_SEED` (2000),
  `MAX_PER_DIRECTORY` (0 = bez limitu; jinak page-granulární ~80), `OUTPUT`.
- Reálný výsledek seed grafu: **1192 unikátních ne-bot účtů** (461 z mastodon.social);
  directory CZ/SK instancí přidá další lokální účty.

## `update_catalog.rb` — inkrementální aktualizace

Udržuje `data.json` živý: nové účty zkategorizuje (platí se jen za ně),
u stávajících obnoví metriky bez AI.

```bash
ruby bin/update_catalog.rb --dry-run                 # jen diff + odhad ceny (nic nemění)
ruby bin/update_catalog.rb --no-categorize           # nové účty jen vypíše do new_candidates.json
ANTHROPIC_API_KEY=... ruby bin/update_catalog.rb     # plná aktualizace + upload na Surfer
```

| Krok | Co dělá | Cena |
|---|---|---|
| Diff | nové účty (nejsou v katalogu dle `id`) vs. stávající | zdarma |
| Refresh stávajících | followers/avatar/bio přes Mastodon lookup; rodina/tagy/popis zůstávají | **zdarma** (bez AI) |
| Kadence refreshe | aktivní každý běh, mlčící ~měsíčně, dlouho mlčící/bez postů ~čtvrtletně | **zdarma** |
| Migrace účtu | `moved` → záznam se přesměruje na novou adresu (metadata zůstanou), dedup dle `id` | **zdarma** |
| Ověření záznamu | úspěch → `last_verified_at`; selhání → `verify_failures` + `unverified_since` | **zdarma** |
| Týdenní přírůstky | `followers_delta`/`activity_delta` = rozdíl proti `metrics_snapshot.json` (Skokani v Účtech) | **zdarma** |
| CZ/SK filtr | lookup+statusy (zdarma), ne-CZ/SK účty přeskočí **před** AI | **zdarma** |
| Kategorizace nových | lookup + posty + Claude (sdílí SYSTEM_PROMPT + caching) | ~$0.0079/účet |

**CZ/SK filtr** (default zapnutý): kandidát se kategorizuje (a platí) jen pokud je
na `.cz`/`.sk` instanci nebo z `instances.txt`, **nebo** má posty v `cs`/`sk`,
**nebo** výraznou českou/slovenskou diakritiku v bio/postech. Ostatní (např.
angličtí uživatelé z mastodon.social) se přeskočí zdarma → nižší cena + čistý
CZ/SK katalog. Vypnutí: `--no-czsk-filter`. Log na konci hlásí počet přeskočených
a uspořenou částku.

ENV: `ANTHROPIC_API_KEY`, `AI_MODEL`, `AI_DELAY`, `MASTODON_DELAY`, `MASTODON_TOKEN`,
`CATALOG_PATH` (web/data.json), `CANDIDATES_PATH` (discovered_accounts.json),
`STATUSES_LIMIT` (20), `LIMIT_NEW` (0 = bez limitu), `SURFER_*`.
Flagy: `--dry-run`, `--no-categorize`, `--no-refresh`, `--no-upload`,
`--no-czsk-filter`, `--recheck-skipped`, `--retype`, `--refamily`. Původní `data.json`
se zálohuje (`.bak`).

**Typ účtu** (`type`): AI klasifikuje `person` / `team` / `institution` / `media` /
`other` (default `person`) — shodné s filtrem na webu. Nové účty dostanou typ při
kategorizaci. Přeznačení stávajících: `--retype` projede **aktivní** účty (≤90 dní)
a přeurčí jen `type` z uloženého bia (bio-only → levné, ~$0.004/účet), s checkpointem
a throttle uploadem.

**Rodina** (`family`): `news` / `sport` / `culture` / `science_tech` / `humor` /
`government` / `local` / `lifestyle` — shodné s filtrem na webu. Model klasifikuje
do PoC rodin, `AI::FAMILY_MAP` je překlápí na katalogové; **chybějící klíč v mapě
znamená tichý pád do `lifestyle`**, proto `lib/ai.rb` při načtení ověří, že mapování
pokrývá celé `FAMILIES`. Přeznačení stávajících: `--refamily` projede **aktivní**
účty v koši `lifestyle` (přebij přes `REFAMILY_FROM=a,b`) a přeurčí `family` +
`categories`. Na rozdíl od `--retype` potřebuje i posty (rodina se řídí převažujícím
tématem, ne biem), takže stojí jako nový účet (~$0.0079/účet).

**Kadence refreshe** (`REFRESH_DORMANT_DAYS` 28, `REFRESH_SILENT_DAYS` 91,
`DORMANT_DAYS` 365): tři čtvrtiny katalogu tvoří účty, které nikdy nic nenapsaly
nebo mlčí přes rok — obnovovat jim followers každý týden nic nepřinese a stojí to
většinu času celého běhu. Aktivní účty (≤ `ACTIVE_DAYS`) se obnovují každý běh,
mlčící 90–365 dní ~měsíčně, dlouho mlčící a účty bez jediného postu ~čtvrtletně.
Rozhoduje `last_verified_at`; záznam bez něj se obnoví vždy. Vynucení: `--refresh-all`
(nebo `REFRESH_ALL=1`).

*Cena za to:* účet, který se po roce mlčení rozmluví, se v katalogu projeví až při
svém dalším refreshi (do ~3 měsíců). Jeho posty se ale ve **Vyhledávání** objeví
hned, pokud je jeho instance skrapovaná.

**Stáří dat** (`last_verified_at` / `unverified_since` / `verify_failures`):
selhaný lookup neznamená „účet se nezměnil", ale „nevíme". Bez značky by zaniklý
účet držel `followers` i `last_status_at` z posledního úspěšného běhu napořád
a tvářil se jako čerstvé číslo — což zkresluje i souhrnné statistiky scény.
Refresh proto u úspěchu zapíše datum ověření, u selhání načte počítadlo a datum
prvního selhání (a při dalším úspěchu je zase smaže). Hodnoty samotné nepřepisuje.

**Cache přeskočených** (`skipped_noncz.json`): ne-CZ/SK účty, které filtr zamítl,
se uloží a příští běh je už vůbec nedotazuje (žádné opakované lookup+statusy).
Dramaticky zrychluje opakované/dávkové běhy i týdenní cron. Reset/přehodnocení:
`--recheck-skipped` (užitečné, když se zlepší heuristika filtru).

**Ruční zařazení účtů** (`manual_accounts.txt`): handle (jeden na řádek), které
chceš v katalogu napevno i proti automatice — typicky **boty** (objevování je
vyřazuje) nebo účty mimo CZ/SK filtr. `update_catalog` je vynuceně zařadí (obejde
filtr i vyřazení botů), zkategorizuje a označí `bot: true`; metriky vč.
`last_status_at` se jim refreshují jako ostatním. Přežije i rebuild data.json.

**Odstranění účtu** (`blocklist.txt`): handle (jeden na řádek), které se **vždy
vyřadí z celé pipeline** — ne jen z katalogu. Uplatňují ho `update_catalog`
(data.json + kandidáti), `build_search` (search.json i users.json, včetně už
postaveného indexu), `collect_posts` (katalogové účty i lokální timeline feedů)
a `consolidate_posts` (žebříčky týdne). Přebije discovery i `manual_accounts.txt`.
Slouží pro žádosti vlastníků o odstranění (patička webu). Pouhé smazání
z data.json nestačí — discovery by účet znovu přidala, a vyhledávání si posty
tahá z timeline instancí úplně mimo katalog.

Porovnání je **case-insensitive** (Mastodon handle je nezávislý na velikosti
písmen), takže `@Franta@x.cz` v blocklistu zabere i na `@franta@x.cz`.

**Cyklus v produkci:** `discover_accounts.rb` (rozšíří kandidáty) →
`update_catalog.rb` (dokategorizuje nové, refreshne staré, uploadne).
První plný běh ~1165 účtů ≈ $9; další týdny jen přírůstek (jednotky $).

## `collect_posts.rb` — denní sběr postů

```bash
ruby bin/collect_posts.rb                          # dnešní den (UTC)
ruby bin/collect_posts.rb --yesterday              # předchozí den (pro běh po půlnoci)
DATE_OVERRIDE=2026-06-01 ruby bin/collect_posts.rb # konkrétní den
ruby bin/collect_posts.rb --dry-run                # bez zápisu
```
ENV: `MASTODON_TOKEN`, `MASTODON_DELAY`, `DATA_JSON_PATH` (data.json),
`OUTPUT_DIR` (.), `MIN_FOLLOWERS` (20).

- **`MIN_FOLLOWERS`:** sbírej posty jen z účtů s aspoň tolika sledujícími.
  Měřeno na 1192 účtech: **top dle followers drží 99,9 % dosahu**; práh 20 vynechá
  ~548 účtů. `MIN_FOLLOWERS=0` = bez prahu.
- Dedup dle `id`; posty bez textu (jen média) se zahrnují; `engagement = reblogs + favs`.
- `hashtags` z API pole `tags` (lowercase, bez `#`, unikátní).
- **`feeds.txt` (obsahové instance):** navíc stáhne **denní lokální timeline** těchto
  instancí (vč. botů) → posty projdou stejnými žebříčky jako katalogové. Katalog
  (Účty) i discover je ignorují.

### Škálovací optimalizace (sdílené přes `lib/mastodon_api`)

1. **Uložené `mastodon_id`** v `data.json` → collect přeskočí lookup (2 → 1 request/účet).
2. **`min_id` přírůstkový sběr** — stav per účet v `collect_state.json`; stáhne jen novější posty.
3. **Per-instance rate limit** — čte `X-RateLimit-*` zvlášť pro každou instanci,
   čeká do resetu jen pro vyčerpanou instanci, 429 respektuje `Retry-After` a opakuje.

## `consolidate_posts.rb` — týdenní konsolidace

```bash
ruby bin/consolidate_posts.rb                              # minulý týden → upload
WEEK_OVERRIDE=2026-W22 ruby bin/consolidate_posts.rb       # konkrétní týden
INPUT_JSONL=/tmp/x.jsonl ruby bin/consolidate_posts.rb --dry-run
```
ENV: `OUTPUT_DIR` (.), `WEEK_OVERRIDE`, `INPUT_JSONL`, `SURFER_*`, `KEEP_JSONL=1`,
`RESCORE=0`, `RESCORE_LIMIT`.
- Sekce `posts.json` (každá max 50): `top_by_engagement`, `top_by_reblogs`,
  `top_by_favourites`, `top_by_date`, `risers`.
- **Přeměření engagementu:** `collect_posts` ukládá boosty/oblíbení v okamžiku
  sběru, tedy 15 min až 24 h po publikaci (podle denní doby). Řadit taková čísla
  mezi sebou znamená řadit podle délky expozice, ne podle úspěchu — konsolidace
  proto všechna čísla stáhne znovu, najednou (`GET /api/v1/statuses/:id`).
  Smazané posty (404/410) vypadnou; neověřené si podrží hodnoty ze sběru.
  Vypnutí: `RESCORE=0`, omezení počtu: `RESCORE_LIMIT=N`.
- **Skokani** (`risers`): `score = engagement − průměr_účtu`; účty s < 3 posty vyloučeny.
- JSONL se maže až po úspěšném uploadu (nebo když Surfer není konfigurován).

## `build_search.rb` — index pro vyhledávání

```bash
ruby bin/build_search.rb                 # přírůstkově (denní cron) + upload
ruby bin/build_search.rb --rebuild       # plný build od nuly (ignoruje stav i index)
RETENTION_DAYS=7 ruby bin/build_search.rb
ruby bin/build_search.rb --no-catalog --no-upload
```
Buduje dva soubory pro **vyhledávání v prohlížeči** (deterministické, bez backendu):
- `web/search.json` — posty v štíhlém schématu: text drží jen `content_html`
  (menší soubor); `content_plain`/`content_folded` dopočítá frontend při načtení.
  Index se navíc **nestahuje na landing**, ale až při prvním dotazu/focusu.
- `web/users.json` — účty = autoři postů ∪ katalog (+ folded pole `f`)

Zdroje: (1) **lokální veřejné timeline** CZ/SK instancí (`config/instances.txt`),
(2) **katalogové účty** (`web/data.json`) — ale jen ty na instancích, které timeline
**nepokryje**: neskrapované (mimo `instances.txt`) nebo skrapované s **nedostupnou**
timeline. Tím denní běh nepolluje všech ~2500 účtů jednotlivě. Z nich se navíc
**mlčící účty** (bez příspěvku déle než `ACTIVE_DAYS`) dotazují jen jednou za
`SEARCH_POLL_INACTIVE_DAYS` (default 7), ne 4× denně — stav si drží
`search_state.json` pod klíčem `poll:<handle>`.
(3) **„obsahové" instance** (`config/feeds.txt` — boti/zprávy, např. `zpravobot.news`):
indexují se do vyhledávání vč. botů, ale s **kratší retencí** `FEEDS_RETENTION_DAYS`
(default 7 dní), aby velký objem nenafoukl `search.json`.

Přírůstkově: navazuje na existující index + stav (`data/search_state.json`, poslední
viděné status id per zdroj), stáhne jen novější posty, dedupne a vyřadí starší než
`RETENTION_DAYS` (30). Diakritika se skládá NFKD (`fold`) shodně jako v klientu.

**Okno obnovy počtů** (`SEARCH_REFRESH_DAYS`, default 2; `FEEDS_REFRESH_DAYS`, default 1):
u postů mladších než tahle hranice se nezastavíme na posledním viděném id, ale
projdeme je znovu a přepíšeme boosty/oblíbení. Bez toho by si post zaindexovaný
pár minut po publikaci nesl svoje nuly celou retenci — a Skokani ve Vyhledávání
se z těch čísel počítají. Nestojí to requesty navíc za jednotlivé posty: čerstvá
čísla přijdou v týchž stránkách timeline, jen se u nich nezastavíme dřív.

## `build_instances.rb` — přehled instancí

```bash
ruby bin/build_instances.rb              # build + upload
ruby bin/build_instances.rb --no-upload  # jen lokálně
MIN_CATALOG=3 ruby bin/build_instances.rb
```
Pro každou instanci stáhne `/api/v2/instance` (+ `/api/v1/instance` pro `stats`) a
sestaví `web/instances.json` (název, popis, logo, uživatelé, aktivní/měs., posty,
stav registrací, jazyky, verze, počet našich katalogových účtů). Zahrnuje CZ/SK
instance (`instances.txt`, příznak `czsk=true`) **a** obecné instance s ≥`MIN_CATALOG`
(3) českými/slovenskými účty z katalogu (mimo bridge). Klient řadí CZ/SK napřed.
Pokud existuje cache `data/instance_topics.json`, připne ke každé instanci `categories`
(oblasti) — sám AI **nevolá**.

## `classify_instances.rb` — zaměření (oblast) instancí

```bash
ruby bin/build_instances.rb                       # 1) vytvoří instances.json (zdroj hostů+popisů)
ANTHROPIC_API_KEY=… ruby bin/classify_instances.rb  # 2) naplní cache zaměření
ruby bin/build_instances.rb                       # 3) připne kategorie + upload
ruby bin/classify_instances.rb --dry-run          # nic nezapíše, jen report
ruby bin/classify_instances.rb --rebuild          # přepočítej i to, co je v cache
```
Mastodon API **nemá** pole „kategorie instance", proto zaměření odvozujeme do cache
`data/instance_topics.json` (`host → {categories, source, desc_hash}`):
- **primárně** z oficiálního katalogu **joinmastodon.org** (`api.joinmastodon.org/servers`),
- **kde chybí** → **AI** klasifikuje popis instance (jak se sama prezentuje) do **stejného**
  číselníku kategorií. AI se volá jen pro **nové/změněné** popisy (hash) → levné.

Číselník = kategorie joinmastodon: `general, academia, activism, art, books, food, furry,
games, journalism, lgbt, music, regional, tech` (frontend je zobrazí česky ve filtru
„Oblast"). Skript běží **zřídka** (týdně/ručně); denní `build_instances` jede bez AI klíče.

## Cron

Viz `config/crontab.example` (volá root wrappery `collect.sh`/`build-search.sh`/
`consolidate.sh`/`discover.sh`/`update.sh`/`classify-instances.sh`/`build-instances.sh`):

Všechny časy jsou **lokální čas serveru** (Cloudron cron běží v TZ kontejneru,
CET/CEST = UTC+1/+2; `CRON_TZ` se neuplatní). Záměrně zvolené tak, aby denní collect
běžel těsně po UTC půlnoci v obou režimech DST.

Denně:
- **collect** **02:15** (= těsně po UTC půlnoci) za předchozí uzavřený UTC den
  (`--yesterday`) → sbírá právě uzavřený den (lag ~15 min, ne ~22 h).
- **build-search** **každých 6 h** (02/08/14/20) — přírůstkový index vyhledávání
  → `search.json` + `users.json` + `status.json`. Čerstvost vs. upload (~21 MB/běh);
  6 h je rozumný kompromis. Plný rebuild ručně: `./build-search.sh --rebuild`.

Týdně (pondělí) — **jeden** cron řádek `weekly.sh` v **03:15** (až po pondělním
collectu 02:15, aby konsolidace měla i neděli), který spustí celý řetěz **sekvenčně**:
1. **consolidate** (týdenní žebříčky postů → `posts.json`)
2. **discover** (přegeneruje kandidáty z instancí + grafu)
3. **update_catalog** (refresh + týdenní přírůstky + dedup + dokategorizace nových)
4. **refresh-instances** (přehled + „Oblast" instancí → `instances.json`)

Řetězení (místo časovaných řádků s mezerami) drží pořadí i závislosti bez ohledu
na délku kroků — refresh-instances tak nikdy neběží nad polovičně updatovaným
katalogem. Selhání jednoho kroku nezastaví zbytek. Stavové značky → `logs/weekly.log`,
detaily do logů jednotlivých kroků.

`refresh-instances.sh` zřetězí **build (lokálně) → classify → build (upload)**, takže
i čerstvě přidaná instance dostane „Oblast" **hned** (vyřešená dvoufázová závislost);
classify když selže, upload se stejně dokončí s kategoriemi z cache. Pořadí v pondělí
je důležité: collect → consolidate → discovery → update (jinak by se nové účty nedostaly
do katalogu / neděle by chyběla v žebříčku). Instance jsou týdně schválně — statistiky/
katalog/kategorie se mění týdně, denně by jen zbytečně tlouklo API.

**Logování:** wrappery si přesměrování řeší samy — z cronu (bez terminálu) zapisují do
`logs/<jméno>.log`, ručně spuštěné píšou na obrazovku (`[ -t 1 ] || exec >> logs/… 2>&1`).
Cron řádky proto NEobsahují `>> logs/… 2>&1`. Cron má holé prostředí → ruby musí být
v PATH (v Cloudron cronu už je).

**Na cronu běží jen PROD** (`PROJECT_DIR=/app/data/slonik`). Test se nebuilduje
paralelně — data se do něj kopírují z produkce přes `./scripts/sync_data_to_test.sh`.
`crontab` je per-uživatel, takže běží jen jeden set (prod); test je pro vývoj ručně.

---

# Web (`web/`)

Statický web (vizuál sdílí s produkčním `katalog.zpravobot.news`). Navigace
**Vyhledávání | Instance | Účty | Posty | Odkazy | O Sloníku** + **CZ | EN** je
ve **sticky liště pod herem** (ne přes obrázek). Na mobilu (≤760 px) se sbalí do
**hamburger draweru** = „Pohledy" (navigace) + kontextové filtry pohromadě.

- **Odkazy:** kurátorovaný rozcestník článků/návodů o Mastodonu (`web/links.js`),
  filtr podle typu (vysvětlení/návody/provozovatel/kontext) a jazyka, karty
  seskupené dle typu. Edituje se ručně v `links.js`.

- **Účty:** filtr rodiny / jazyka / tagů, vyhledávání, řazení, modal detailu,
  rozlišení osoba vs. bot (badge), avatary z Mastodon CDN s fallbackem.
  Zobrazují se jen **aktivní účty** — poslední příspěvek do `ACTIVE_DAYS` (90)
  dní; účet bez `last_status_at` se zatím ukáže (pole doplní příští refresh).
  `last_status_at` ukládá `update_catalog.rb` (categorize + refresh).
- **Posty:** lazy-load `posts.json`, řazení (boosty+favy / boosty / favy / nejnovější /
  skokani), Top 10 / Top 50, klikatelné hashtagy + zmínky + URL, filtr Oblast/Vyhledat/Hashtagy.
  Fallback bez `posts.json`: „Posty jsou dostupné každý týden v pondělí ráno."
- **Instance:** adresář CZ/SK instancí (kde si založit účet) + obecné instance, kde
  máme české účty; karty s logem, statistikami (uživatelé / aktivní měs. / posty),
  stavem registrací a CTA „Založit účet". Lazy-load `instances.json` (`build_instances.rb`).
  Dvě sekce: komunitní CZ/SK (`czsk`) a obecné (`other`). Pod titulkem žebříčky
  (Vše / Top 10 / Top 50 / Poměrem = podíl aktivních / Objemem = počet příspěvků),
  vlevo Vyhledat, Řadit a filtr **Oblast** (zaměření instance z `classify_instances.rb`).
- **Vyhledávání:** deterministické fulltextové hledání v prohlížeči (bez backendu/LLM)
  nad `search.json` (posty, 30 dní) + `users.json` (účty). Sjednocený box, dvě sekce
  (Účty / Posty); diakritika se skládá (NFKD) shodně na serveru i v klientu. Karty
  se sdílí s taby Účty/Posty. Lazy-load při prvním otevření tabu.
- **O Sloníku:** statická stránka s levým menu a 3 sekcemi.
- Stav v URL hash: `#view=ucty|posty|instance|search|about` (+ `psort`, `ptop`,
  `phash`; `sq` = hledaný dotaz).

Náhled: `ruby bin/serve.rb 8765 web` → http://127.0.0.1:8765/
Nasazení: viz `web/DEPLOY.md` (upload na Surfer přes Files API).

---

# Klíčové poznatky z PoC

- **Token není pro katalog nutný** — directory + statusy jsou veřejné všude
  (jen lokální timeline na velkých instancích vrací 422).
- **AI kategorizace:** sonnet, 50/50 účtů bez chyb; ~$0.0079/účet. Prompt caching
  šetří jen ~7 % (většina promptu je per-účet variabilní data, ne sdílený systém).
- **Slovensko:** jediná ověřeně živá ryze SK instance je `mastodon.sk`; ostatní SK
  účty žijí na CZ/velkých instancích a dolují se heuristikou jazyka (`dominant_language == "sk"`).
- **Mrtvé instance:** `mastodon.cz` (zaparkovaná doména / rozbitý TLS) — vyřazena.
- Historické reporty a data: `archiv/` (`poc_report.md`, `ai_report.md`, `poc_results.json`).
