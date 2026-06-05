# Nasazení makety na `katalog-test.zpravobot.news`

PoC maketa je hotová ve složce `web/`. Nasazení se dělá přes **Surfer
Files API** (Cloudron). `posts.json`/`data.json` uploadují skripty samy
(`Surfer.upload` v `lib/config.rb`); statické assety níže lze nahrát ručně.

## Obsah k nahrání

Nahraj **obsah složky `web/`** do rootu Surfer instance:

```
index.html      # upravený název → "Fediverse katalog CZ/SK"
app.js          # produkční + 2 řádky i18n (brand_prefix, title_doc, claim)
app.css         # beze změny (identický s produkcí)
data.json       # 50 CZ/SK lidí + 25 botů, s polem `bot`
header.jpg      # beze změny (placeholder = produkční header)
```

> `DEPLOY.md` a `avatars/` (prázdná) nahrávat netřeba.

## Upload přes Surfer Files API (příklad)

Surfer **nepoužívá WebDAV**. Upload je `POST /api/files/<name>?access_token=…&newFilePath=<name>`
(multipart, pole `file`, úspěch HTTP 201). Doplň URL a access_token:

```bash
cd web
BASE="https://katalog-test.zpravobot.news"
TOKEN="..."   # Surfer access_token (Settings → Access tokens)

for f in index.html app.js app.css data.json header.jpg; do
  curl -sf -X POST -F "file=@$f" \
    "$BASE/api/files/$f?access_token=$TOKEN&newFilePath=$f" \
    && echo "uploaded $f"
done
```

(Stejné credentials jako `SURFER_URL`/`SURFER_TOKEN` v `config.env`. Datové soubory
`data.json`/`posts.json` ale typicky nahrávají skripty samy.)

## Po nahrání ověř

- [ ] `https://katalog-test.zpravobot.news/` se načte
- [ ] Titulek je „Fediverse katalog CZ/SK"
- [ ] Zobrazuje se 75 zdrojů (50 lidí + 25 botů)
- [ ] Avatary se načítají (přímé URL z Mastodon CDN — vyžaduje, aby je
      prohlížeč návštěvníka stáhl z `witter.cz`/`mastodonczech.cz`/`mamutovo.cz`)
- [ ] Filtry / hledání / řazení fungují

## Pozn. k avatarům

`data.json` používá **přímé URL** na Mastodon CDN jednotlivých instancí
(dle dohody). Výhoda: žádné soubory k nahrání. Nevýhoda: pokud instance avatar
smaže/přesune, app.js spadne na `avatar-fallback` (iniciála na barevném pozadí) —
to je očekávané a graceful.

## Lokální náhled (bez nasazení)

```bash
ruby bin/serve.rb 8765 web
# → http://127.0.0.1:8765/
```
