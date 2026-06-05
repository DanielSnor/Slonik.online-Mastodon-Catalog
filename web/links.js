/* Kurátorovaný seznam zdrojů o Mastodonu pro tab „Odkazy".
   Edituj ručně. Pole: title, url, source, lang (cs|en),
   type (explainer|navod|provozovatel|kontext), freshness, note. */
window.SLONIK_LINKS = [
  // ── Česky — Explainery ──
  {
    "title": "Co je to Mastodon, jak funguje a proč ho používat",
    "url": "https://www.zive.cz/clanky/co-je-to-mastodon-fediverse-activitypub/sc-3-a-219295/default.aspx",
    "source": "Živě.cz", "lang": "cs", "type": "explainer", "freshness": "2022-11",
    "note": "Nejobsáhlejší český vysvětlovák. Rozdíl centralizované vs. federované sítě, ActivityPub, srovnání protokolů. Dobrý jako hlavní „co to je“."
  },
  {
    "title": "Malý, ale náš. Sociální síť Mastodon vrací pravidla do rukou uživatelů",
    "url": "https://www.irozhlas.cz/veda-technologie/technologie/mastodon-socialni-site-twitter-elon-musk_2211230620_cib",
    "source": "iROZHLAS", "lang": "cs", "type": "explainer", "freshness": "2022-11",
    "note": "Novinářský úvod. Princip instance jako „zmenšené kopie“ sítě a propojení napříč instancemi."
  },
  {
    "title": "Lidé prchají z Twitteru na novou síť. Co je to Mastodon a jak funguje?",
    "url": "https://mobilizujeme.cz/clanky/co-je-to-mastodon-a-jak-funguje",
    "source": "Mobilizujeme.cz", "lang": "cs", "type": "explainer", "freshness": "2025-01",
    "note": "Neziskový charakter, založení Eugenem Rochko, financování crowdfundingem, otevřený kód."
  },
  {
    "title": "Mastodon, copa to je?",
    "url": "https://jndm.cz/2022-11-12-mastodon-copa-to-je/",
    "source": "JndM.cz (Michal Janda)", "lang": "cs", "type": "explainer", "freshness": "2022-11",
    "note": "Lehký, lidský úvod s e-mailovou analogií a doporučením serverů."
  },

  // ── Česky — Návody ──
  {
    "title": "Jak založit (vytvořit) účet na Mastodonu — krok po kroku",
    "url": "https://365tipu.cz/2022/11/19/tip2295-jak-zalozit-vytvorit-ucet-na-mastodonu-postup-krok-po-kroku/",
    "source": "365tipů (Daniel Dočekal)", "lang": "cs", "type": "navod", "freshness": "2022-11",
    "note": "Doslovný klikací postup pro úplné začátečníky (Vytvořit účet → pravidla → jméno)."
  },
  {
    "title": "Přestěhovat se z Twitteru na Mastodon? Jak na Mastodon",
    "url": "https://365tipu.cz/2022/10/31/tip2279-prestehovat-se-z-twitteru-na-mastodon-jak-na-mastodon/",
    "source": "365tipů (Daniel Dočekal)", "lang": "cs", "type": "navod", "freshness": "2022-10",
    "note": "Řeší správný tvar adresy (@jmeno@server) a typické chyby při zápisu handle."
  },
  {
    "title": "Jak začít rychle používat Mastodon",
    "url": "https://wiki.arch-linux.cz/books/mastodon/page/jak-zacit-rychle-pouzivat-mastodon",
    "source": "Arch Linux CZ wiki", "lang": "cs", "type": "navod", "freshness": "undated",
    "note": "Nejlepší český onboarding. Výběr serveru, profil, první příspěvek, jazyk rozhraní i jazykový filtr. Tip na import CSV se 100 nejsledovanějšími CZ účty."
  },
  {
    "title": "Jak začít s novým „Twitterem“ a co od této sítě můžeš čekat",
    "url": "https://refresher.cz/125461-Mastodon-Jak-zacit-s-novym-Twitterem-a-co-od-teto-site-muzes-cekat",
    "source": "Refresher.cz", "lang": "cs", "type": "navod", "freshness": "2022-11",
    "note": "Návod s důrazem na komunitní étos a psaní profilu."
  },
  {
    "title": "Mastodon (rozcestník)",
    "url": "https://wiki.pirati.cz/to/technicke-systemy/mastodon",
    "source": "Pirati.cz wiki", "lang": "cs", "type": "navod", "freshness": "undated",
    "note": "Stručný rozcestník + doporučené aplikace (Android: Tusky, Fedilab; iOS: Mastodon, Toot, Mercury)."
  },

  // ── Česky — Pro provozovatele ──
  {
    "title": "Jak na Mastodon — sociální síť, která je alternativou Twitteru",
    "url": "https://medium.seznam.cz/clanek/frantisek-fuka-jak-na-mastodon-socialni-sit-ktera-je-alternativou-twitteru-1130",
    "source": "Seznam Médium (František Fuka)", "lang": "cs", "type": "provozovatel", "freshness": "2022-12",
    "note": "Nejostřejší český text. Boří mýtus „Mastodon = sociální síť“ a otevřeně řeší právní/technické důsledky federace pro správce serveru (cizí obsah ve vlastní databázi). Povinné čtení pro provoz instance."
  },

  // ── Česky — Kontext / scéna ──
  {
    "title": "Na Mastodonu už je i vláda. Trendy síť láká taky extremisty a esoteriky",
    "url": "https://www.irozhlas.cz/veda-technologie/technologie/mastodon-vlada-socialni-sit-extremiste-esoterici_2211240600_mkl",
    "source": "iROZHLAS", "lang": "cs", "type": "kontext", "freshness": "2022-11",
    "note": "Mapuje největší CZ servery (MastodonCzech/Lupa, Piráti, Witter.cz, Arch Linux CZ) a nástup institucí."
  },
  {
    "title": "Spouštíme MastodonCzech.cz",
    "url": "https://www.lupa.cz/clanky/spoustime-mastodonczech-cz-chcete-vyzkouset-decentralizovanou-obdobu-twitteru/",
    "source": "Lupa.cz (David Slížek)", "lang": "cs", "type": "kontext", "freshness": "2022-11",
    "note": "Historický milník české scény; spuštění největší CZ instance, úvod k sérii textů o fediverse."
  },
  {
    "title": "Svobodný Mastodon ve svobodném Fediversu",
    "url": "https://denikalarm.cz/2026/04/svobodny-mastodon-ve-svobodnem-fediversu/",
    "source": "Deník Alarm", "lang": "cs", "type": "kontext", "freshness": "2026-04",
    "note": "Nejnovější a nejhlubší český esej. Mastodon v kontextu svobodného softwaru + dynamika defederace (#fediblocks)."
  },

  // ── Anglicky ──
  {
    "title": "Mastodon and the Fediverse — Beginners Start Here",
    "url": "https://fedi.tips/",
    "source": "Fedi.Tips (@FediTips)", "lang": "en", "type": "navod", "freshness": "current",
    "note": "Zlatý standard. Neoficiální, netechnický, psaný lidmi bez AI. Krátké klikatelné sekce. Doporučuje NEregistrovat se na mastodon.social."
  },
  {
    "title": "The 5-minute guide to the fediverse and Mastodon",
    "url": "https://gist.github.com/joepie91/f924e846c24ec7ed82d6d554a7e7c9a8",
    "source": "joepie91 (GitHub Gist)", "lang": "en", "type": "explainer", "freshness": "undated",
    "note": "Minimum textu, maximum podstaty. Důraz na fediverse jako prostor pro blízké komunity, ne „globální náměstí“."
  },
  {
    "title": "How to join Mastodon (and the fediverse)",
    "url": "https://stefanbohacek.com/blog/how-to-join-mastodon-and-the-fediverse/",
    "source": "Stefan Bohacek", "lang": "en", "type": "navod", "freshness": "2026-03",
    "note": "Aktuální, střízlivé. „Nepřemýšlejte nad výběrem serveru — jde snadno změnit.“ Skvělý rozcestník dalších zdrojů."
  },
  {
    "title": "A Simple Guide to Mastodon (And the Fediverse)",
    "url": "https://www.staygrounded.online/p/a-simple-guide-to-mastodon-and-the",
    "source": "staygrounded.online (Justin)", "lang": "en", "type": "explainer", "freshness": "2023-09",
    "note": "Nejlepší vysvětlení federace a odolnosti sítě (software nelze koupit → vznik nových instancí je triviální)."
  },
  {
    "title": "Getting Started With Mastodon and the Fediverse",
    "url": "https://geekmom.com/2023/10/getting-started-with-mastodon-and-the-fediverse/",
    "source": "GeekMom", "lang": "en", "type": "navod", "freshness": "2023-10",
    "note": "Přátelský úvod, nejlepší e-mailová analogie, přesah na PixelFed a PeerTube."
  },
  {
    "title": "How to get started on Mastodon / The Fediverse",
    "url": "https://www.kristofferlislegaard.com/blog/2025-01-25-how-to-get-started-on-mastodon-fediverse/",
    "source": "Kristoffer Lislegaard", "lang": "en", "type": "navod", "freshness": "2025-01",
    "note": "Důraz na to, co je jiné: #Introduction post, jazyková nastavení, filtrování feedu klíčovými slovy."
  }
];
