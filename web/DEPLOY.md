# Publikace webu na Surfer

Web je statický a nahrává se přes **Surfer Files API** (Cloudron), stejnou cestou
jako datové soubory: `POST /api/files/<name>?access_token=…&newFilePath=<name>`
(multipart, pole `file`, úspěch HTTP 201). Sdílená implementace je `Surfer.upload`
v `lib/config.rb`.

Podrobný deploy řetězec (Mac → server → Surfer) je v kořenovém `README.md`,
sekce „Nasazení na server". Tenhle soubor popisuje jen poslední krok.

## Co se nahrává

| Skupina | Soubory | Kdo je publikuje |
|---|---|---|
| Frontend | `index.html`, `app.js`, `app.css`, `links.js`, obrázky | ručně `./deploy-web.sh --assets` |
| Katalog | `data.json`, `status.json` | `update_catalog.rb` sám |
| Žebříčky | `posts.json`, `weekly.json` | `consolidate_posts.rb` sám |
| Vyhledávání | `search.json`, `users.json` | `build_search.rb` sám |
| Instance | `instances.json` | `build_instances.rb` sám |
| Obrázky | `avatars/`, `logos/` | `cache_images.rb` sám (jen nové + mazání starých) |

Datové soubory tedy ručně nahrávat netřeba — dávkové skripty je publikují samy po
každém běhu. `./deploy-web.sh --assets` použiješ po změně frontendu,
`./deploy-web.sh` nahraje celý bundle.

> `web/data.json` je **publikovaná** verze katalogu (jen pole, která frontend
> vykresluje). Plné záznamy jsou v `data/catalog.json` a na web nepatří —
> viz README, sekce „Katalog: úložiště vs. web".

## Ruční upload (když je potřeba obejít skripty)

```bash
cd web
BASE="https://slonik.online"
TOKEN="..."   # Surfer access_token (Settings → Access tokens)

for f in index.html app.js app.css links.js; do
  curl -sf -X POST -F "file=@$f" \
    "$BASE/api/files/$f?access_token=$TOKEN&newFilePath=$f" \
    && echo "uploaded $f"
done
```

Stejné credentials jako `SURFER_URL`/`SURFER_TOKEN` v `config.env`.

## Po nahrání ověř

- [ ] `https://slonik.online/` se načte a v patičce sedí datum aktualizace katalogu
- [ ] Účty: počet odpovídá aktivním účtům (ne celému katalogu)
- [ ] Filtry oblastí obsahují **Region**, ne „Byznys"
- [ ] Vyhledávání najde výsledky (stahuje `search.json`, řádově MB)
- [ ] Posty ukazují poslední uzavřený týden
- [ ] Loga instancí i avatary se načítají z `slonik.online`, ne z cizích domén
- [ ] Konzole prohlížeče je bez chyb — hlavně bez porušení CSP

## Pozn. k obrázkům

Avatary i loga instancí se publikují jako **zmenšené kopie** ve `web/avatars/`
a `web/logos/` — nahrává je `cache_images.rb`, `deploy-web.sh` se jich netýká.
Jméno souboru je hash zdrojové URL, takže se přenášejí jen nově přibylé a smazané.
Když kopie chybí, frontend zkusí původní vzdálenou adresu (s
`referrerPolicy="no-referrer"`) a jinak vykreslí iniciálu na barevném pozadí.

## Lokální náhled (bez nasazení)

```bash
./serve.sh 8765
# → http://127.0.0.1:8765/
```
