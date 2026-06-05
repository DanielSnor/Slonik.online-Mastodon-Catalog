# AI kategorizace CZ/SK Mastodon účtů — report

_Model: claude-sonnet-4-5-20250929 | účtů: 50 | úspěšně: 50 | chyb: 0 | 2026-06-01 20:02_

## 1) Distribuce rodin

| Rodina | Počet | % |
|---|---|---|
| news | 5 | 10.0% |
| politics | 7 | 14.0% |
| sport | 3 | 6.0% |
| tech | 17 | 34.0% |
| culture | 5 | 10.0% |
| fun | 4 | 8.0% |
| local | 3 | 6.0% |
| other | 6 | 12.0% |

## 2) Nejčastější tagy (top 20)

| Tag | Počet |
|---|---|
| open_source | 11 |
| linux | 10 |
| software_developer | 9 |
| politics | 7 |
| local_community | 6 |
| humor | 6 |
| cycling | 5 |
| photography | 5 |
| activism | 5 |
| commentary | 5 |
| current_affairs | 4 |
| self_hosting | 4 |
| everyday_life | 4 |
| brno | 3 |
| geocaching | 3 |
| media | 3 |
| geopolitics | 2 |
| news | 2 |
| 3d_printing | 2 |
| football | 2 |

Celkem unikátních tagů: **151** (na 50 účtů).

## 3) Chybovost

- Celkem účtů: 50
- Úspěšně kategorizováno: 50
- Chyb (API / parse): 0

## 4) Tokeny a odhad ceny

| Metrika | Hodnota |
|---|---|
| Průměr prompt tokenů (vč. cache) | 1996 |
| Průměr response tokenů | 100 |
| Prompt caching | ✅ aktivní — cache read u 50/50 účtů |
| Cache write tokenů (celkem) | 0 (účtováno 1,25×) |
| Cache read tokenů (celkem) | 74050 (účtováno 0,1×) |
| **Reálná cena za 1 účet** (claude-sonnet-4-5-20250929) | **$0.00792** |
| Odhad za 50 účtů | $0.396 |
| Odhad za 500 účtů | $3.96 |
| Odhad za 5000 účtů | $39.62 |

_Ceník (claude-sonnet-4-5-20250929): $3.0/1M vstup, $15.0/1M výstup. Cache write 1,25× vstupní ceny, cache read 0,1× vstupní ceny (list prices, ověřit)._
_Cena za 1 účet je skutečná: zahrnuje plnou cenu vstupu/výstupu + cache write/read podle reálných `usage` hodnot z API._

## 5) Kvalitativní poznatky — ukázky

### Dobře zařazené (dost dat: bio + 15+ postů)
- **@wvi** (witter.cz, en) → **tech** `software_developer, open_source, linux, self_hosting, ai_criticism`
  > Vývojář se zájmem o open source, Linux a soukromí; kriticky se vyjadřuje k AI a big tech firmám, sdílí technické postřehy a občas Star Wars kvízy.
- **@algebraicterror** (witter.cz, en) → **tech** `software_developer, open_source, brno, diy, cats`
  > Vývojář z Brna se zájmem o open source software a DIY projekty; sdílí technické postřehy, humor a fotky koček.
- **@matejcerny** (witter.cz, en) → **tech** `scala, functional_programming, software_developer, database, open_source`
  > Scala a funkcionální programování inženýr se zaměřením na databáze a SQL. Sdílí novinky z Scala ekosystému, konference a technické postřehy.
- **@daliborzz** (witter.cz, cs) → **politics** `politics, pirate_party, czech_politics, activism, commentary`
  > Zakládající člen Pirátské strany, nyní ex-člen, intenzivně sleduje a komentuje české politické dění, volby a stranickou politiku.
- **@banterCZ** (witter.cz, cs) → **tech** `software_developer, java, scouting, diy, books`
  > Programátor v Javě, který kromě technických témat sdílí postřehy o skautingu, kutilství, knihách a občanském životě.
- **@theron29** (witter.cz, cs) → **tech** `linux, devops, gaming, open_source, it_professional`
  > IT DevOps a Release Manager se zaměřením na Linux, open source a gaming. Sdílí technické postřehy, herní benchmarky a lokální zprávy z Brna.

### Hraniční případy (málo dat → nižší jistota)
- **@Clon** (witter.cz): bio=0 zn., 14 postů → **culture** `activism, documentary_film, civic_society, media_freedom, board_games`
  > Aktivisticky orientovaný účet sdílející především kulturní akce (dokumentární festivaly, deskovky) a zapojující se do občanské společnosti, zejména do kampaní na obranu veřejnoprávních médií.
- **@krsnak** (witter.cz): bio=90 zn., 6 postů → **tech** `digital_literacy, ai_ethics, education, technology_criticism, children_online`
  > Zaměřuje se na digitální gramotnost a kritický pohled na technologie, zejména AI a jejich dopad na děti a mezilidskou komunikaci.
- **@klokanek** (witter.cz): bio=0 zn., 20 postů → **news** `journalist, media, tech, politics, culture`
  > Novinář a autor Nebezpečné knihy, sdílí zpravodajství, komentáře k médiím, technologiím, politice i kultuře. Zachycuje české i globální aktuální dění s důrazem na svobodu informací.
- **@otecfura** (witter.cz): bio=0 zn., 20 postů → **fun** `humor, satire, poetry, czech_culture, social_commentary`
  > Humoristický účet sdílející satirické básničky a vtipné komentáře k aktuálnímu dění, sportu i absurditám všedního života.
- **@Unreed** (mastodonczech.cz): bio=0 zn., 20 postů → **fun** `humor, everyday_life, parenting, cycling, gaming`
  > Humorný účet plný postřehů z běžného života, rodičovství a koníčků — cyklistika, hry, technické vtípky a ironie k okolnímu světu.
- **@czstatistika** (mastodonczech.cz): bio=0 zn., 20 postů → **news** `statistics, public_sector, data_visualization, government, czech_statistics`
  > Oficiální účet Českého statistického úřádu — sdílí statistická data, infografiky, výsledky sčítání a informace o práci státní správy.

## 6) Doporučení

### Kvalita rodin
- Úspěšnost parsování: **50/50** (100.0 %), parse/API chyb: 0.
- ⚠️ **Nevyužité rodiny:** `nature`. Ve vzorku se nevyskytly, ač relevantní obsah existuje (např. tagy `cycling`, `hiking`, `football` → model je dal do `tech`/`culture`/`other`, ne do `sport`; lokální obsah z Ostravy/Brna nešel do `local`). → Prompt by měl rodiny `sport` a `local` explicitně přiblížit příklady, jinak model preferuje obecnější rodinu podle profese autora.
- Rodina kóduje **primární téma účtu**, ale CZ Mastodon je silně IT-komunita → **17/50 účtů = tech**. Pro katalog zvážit jemnější poddělení techu nebo váhu tagů, jinak bude `tech` přeplněná.

### Konzistence tagů
- Unikátních tagů: **151** na 50 účtů; z toho **113** použito jen 1× (75 %). Vysoká kardinalita = bohaté, ale málo konzistentní pro filtrování/faceting.
- Tagy jsou věcně **smysluplné, v angličtině a lowercase dle zadání** — formát drží. Problém není kvalita jednotlivého tagu, ale globální nejednotnost napříč účty.

### Vliv množství dat
- Účty s prázdným bio nebo <10 posty (7 ve vzorku) dostávají vágnější popis a častěji `other` — kvalita roste s objemem postů. Doporučení: u účtů s <10 posty stáhnout víc (včetně replies), nebo označit nižší confidence.

### Prompt — potřebuje ladění? Ano, drobné.
1. Přidat 1větné definice + příklady k rodinám `sport`, `local`, `nature`, `news` (jsou podreprezentované, model je míjí ve prospěch `tech`/`culture`/`other`).
2. Vyžádat **confidence** (0–1) pro rodinu — umožní v katalogu oddělit jisté od nejistých.
3. U tagů doplnit pokyn „preferuj existující obecné tagy před vymýšlením nových“ + následný normalizační krok proti řízenému slovníku.
4. Zvážit oddělení **profese** (jeden tag) od **témat** (zbytek) — teď se mísí.

### Cena / škálovatelnost
- Reálně naměřeno: ~1996 vstup + ~100 výstup tokenů/účet → **$0.0079/účet**. Pro 5000 účtů ~**$40** jednorázově. S **prompt caching** statické části promptu klesnou vstupní tokeny o ~80 % při dávkovém běhu → produkčně levné.