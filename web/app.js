'use strict';

// Katalog zdrojů Zprávobot.news — vše běží v prohlížeči nad data.json.
// ~540 záznamů → Array#filter/sort stačí, žádné indexování ani framework.
//
// Funkce: filtry (rodina/typ/jazyk/tag), full-text, řezy (platforma/Top N/nedávné),
// řazení, hover preview, detail modal, stav v URL hash, mobilní accordion.

(function () {
  // ---------- i18n ----------
  // Default čeština, ruční přepínač CZ|EN v hlavičce. EN = jen UI shell;
  // obsah (jména, bia, tagy) zůstává v původním jazyce.
  var LANGS = ['cs', 'en'];
  var lang = 'cs';

  var STRINGS = {
    cs: {
      brand_prefix: 'Sloník', brand_domain: 'CZ | SK Mastodon katalog', title_doc: 'Sloník.online — CZ | SK Mastodon katalog',
      claim: 'Objev české a slovenské uživatele na Mastodonu',
      count_of: 'z', count_sources: 'zdrojů',
      nav_platform: 'Platforma', nav_charts: 'Žebříčky', nav_risers: 'Skokani týdne', nav_new: 'Novinky',
      nav_all: 'Vše', nav_top10_foll: 'Top 10 sledovaných', nav_top10_active: 'Top 10 aktivních',
      nav_top50_foll: 'Top 50 sledovaných', nav_top50_active: 'Top 50 aktivních',
      nav_risers_foll: 'V sledujících', nav_risers_active: 'V aktivitě', nav_recent: 'Nedávno přidané',
      filters_toggle: 'Filtry', menu_show: 'Menu', menu_hide: 'Zavřít', nav_views: 'Pohledy',
      nav_slices: 'Žebříčky', head_topic_byaccount: 'Oblast (dle účtu)',
      search_label: 'Vyhledat', search_ph: 'Jméno nebo handle…',
      sort_label: 'Řadit', sort_name: 'Abecedně', sort_followers: 'Nejvíc sledujících',
      sort_posts: 'Nejaktivnější', sort_added: 'Nejnověji přidané',
      head_topic: 'Oblast', head_type: 'Typ účtu', head_language: 'Jazyk', head_tag: 'Tag',
      tag_ph: 'Filtr podle tagu…', reset: 'Zrušit filtry',
      loading: 'Načítám katalog…', empty_title: 'Žádný zdroj neodpovídá filtrům.',
      empty_hint: 'Zkus uvolnit některý z filtrů.', empty_reset: 'Reset filtrů',
      load_error: 'Nepodařilo se načíst data katalogu.',
      footer_indexed: 'Vyhledávání naposledy indexováno',
      footer_updated: 'Katalog naposledy aktualizován',
      footer_owner: 'Jsi vlastník účtu a chceš jej z katalogu odstranit? Napiš na',
      fam_sport: 'Sport', fam_news: 'Zprávy', fam_culture: 'Kultura', fam_science_tech: 'Věda & technika',
      fam_lifestyle: 'Životní styl', fam_business: 'Byznys', fam_humor: 'Humor', fam_government: 'Stát',
      type_person: 'Osoba', type_media: 'Médium', type_institution: 'Organizace',
      type_institution_formal: 'Instituce', type_institution_filter: 'Instituce/Organizace',
      type_team: 'Tým', type_other: 'Ostatní',
      lang_cs: 'Čeština', lang_sk: 'Slovenčina', lang_en: 'English',
      stat_followers: 'sledujících', stat_posts_week: 'příspěvků/týden', stat_language: 'jazyk',
      modal_sources: 'Původní profily', modal_open: 'Otevřít profil', modal_follow: 'Sledovat',
      modal_follow_title: 'Otevře profil, kde můžeš sledovat ze své Mastodon instance', modal_close: 'Zavřít',
      hover_source: 'Zdroj: ', card_detail: 'Detail ',
      slice_platform: 'Zdroje s platformou ', slice_recent_pre: 'Přidané za posledních ',
      slice_recent_post: ' dní', slice_top_pre: 'Top ', slice_top_post: ' (ostatní filtry kromě oblasti jsou vypnuté)',
      top_phrase_followers: 'podle sledujících', top_phrase_active: 'podle aktivity',
      top_phrase_gain_followers: 'podle nárůstu sledujících', top_phrase_gain_activity: 'podle nárůstu aktivity',
      view_accounts: 'Účty', view_posts: 'Posty', view_about: 'O Sloníku', view_search: 'Vyhledávání', view_instance: 'Instance', view_links: 'Odkazy',
      links_nav_title: 'Odkazy',
      links_nav_desc: 'Kurátorovaný rozcestník kvalitních článků a návodů o Mastodonu a fediverse — česky i anglicky. Filtruj podle typu a jazyka.',
      links_head_type: 'Typ', links_count: 'odkazů',
      ltype_explainer: 'Vysvětlení', ltype_navod: 'Návody', ltype_provozovatel: 'Pro provozovatele', ltype_kontext: 'Kontext / scéna',
      lfresh_undated: 'bez data', lfresh_current: 'průběžně aktualizováno', links_zero: 'Žádný odkaz neodpovídá filtrům.',
      accounts_nav_title: 'Účty',
      accounts_nav_desc: 'Katalog českých a slovenských účtů na Mastodonu. Filtruj podle oblasti, typu, jazyka a tagů, vyhledávej podle jména nebo handle a řaď podle počtu sledujících či aktivity. Kliknutím na účet zobrazíš detail.',
      posts_nav_title: 'Posty',
      posts_nav_desc: 'Nejlepší příspěvky českých a slovenských účtů za poslední týden. Přepínej žebříčky (Top 10/50, skokani týdne), filtruj podle oblasti, textu a hashtagů a řaď podle boostů, oblíbených nebo data.',
      instance_nav_title: 'Instance',
      instance_nav_desc: 'České a slovenské Mastodon instance — kde si můžeš založit účet a koho tam najdeš. U každé je velikost, aktivita, stav registrací a kolik je tam účtů z tohoto katalogu. Seřazeno podle velikosti.',
      instance_loading: 'Načítám instance…', instance_unavail: 'Seznam instancí zatím není k dispozici.',
      instance_count: 'instancí', instance_reg_open: 'Registrace otevřené',
      instance_reg_approval: 'Registrace se schválením', instance_reg_closed: 'Registrace zavřené',
      instance_join: 'Založit účet', instance_open: 'otevřít',
      instance_users: 'uživatelů', instance_active: 'aktivních/měs', instance_posts: 'příspěvků',
      instance_catalog: 'v katalogu',
      instance_sec_czsk: 'České a slovenské instance',
      instance_sec_other: 'Další instance s českými/slovenskými účty',
      instance_sec_small: 'Malé / osobní instance',
      instance_search_ph: 'Název nebo doména…',
      isort_users: 'Nejvíc uživatelů', isort_active: 'Nejaktivnější',
      isort_catalog: 'Nejvíc účtů z katalogu', isort_posts: 'Nejvíc příspěvků',
      instance_region_head: 'Oblast',
      irank_activity: 'Aktivita instance', irank_ratio: 'Poměrem', irank_volume: 'Objemem',
      irank_ratio_note: 'podle podílu aktivních uživatelů', irank_volume_note: 'podle celkového počtu příspěvků',
      ssort_relevance: 'Podle shody',
      search_tagline: 'Prohledá účty i příspěvky českého a slovenského Mastodonu — bez ohledu na diakritiku a bez přihlášení.',
      search_tip: 'Tip: víc slov = musí být všechna; přesnou frázi dej do uvozovek („…"), slovo vylučíš mínusem (-slovo).',
      search_ph_view: 'Hledat účty i posty…', search_unit_accounts: 'účtů', search_unit_posts: 'postů',
      search_sec_accounts: 'Účty', search_sec_posts: 'Posty', search_loading: 'Načítám index…',
      search_hint: 'zadej dotaz', search_zero: 'Nic nenalezeno. Zkus jiná / obecnější slova.',
      search_unavail: 'Vyhledávací index zatím není k dispozici.', search_open: 'otevřít na Mastodonu',
      search_posts_active: 'příspěvků (30 dní)', search_followers: 'sledujících',
      search_nav_title: 'Vyhledávání',
      search_nav_desc: 'Hledá v účtech i příspěvcích českého a slovenského Mastodonu. Nezáleží na velikosti písmen ani diakritice (napíšeš „bouzkova", najde „Bouzková"), hledá napříč všemi instancemi naráz a bez přihlášení. Výsledky jsou z posledních týdnů.',
      about_title: 'O Sloníku',
      about_menu_about: 'O Sloníku', about_menu_howto: 'Jak pracovat', about_menu_other: 'Ostatní',
      about_menu_other_desc: 'A nakonec několik závěrečných informací — časté dotazy, technické pozadí, o autorovi a jak projekt podpořit.',
      about_menu_about_desc: 'Sloník je katalog českých a slovenských uživatelů sítě Mastodon. Pomáhá najít zajímavé lidi, média i instituce z našeho prostoru — napříč všemi servery (instancemi), bez ohledu na to, kde mají účet.',
      about_menu_howto_desc: 'Několik tipů, jak co nejlépe využít možností, které Sloník.online poskytuje pro práci s:',
      about_nav_about: 'O Sloníku', about_nav_search: 'Vyhledáváním', about_nav_instance: 'Instancemi',
      about_nav_accounts: 'Účty', about_nav_posts: 'Posty', about_nav_links_howto: 'Odkazy',
      about_nav_tech: 'Technické řešení', about_nav_author: 'O autorovi', about_nav_faq: 'FAQ',
      prisers_ratio: 'Poměrem', prisers_abs: 'Dosahem',
      label_bot: 'Automat', label_bot_title: 'Automatizovaný účet (bot)',
      psort_engagement: 'Nejvíce boostů + favů', psort_reblogs: 'Nejvíce boostů',
      psort_favourites: 'Nejvíce favů', psort_date: 'Nejnovější', psort_date_asc: 'Od nejstaršího',
      posts_loading: 'Načítám posty…', posts_empty: 'Žádný post neodpovídá filtrům.',
      posts_unavailable: 'Posty jsou dostupné každý týden v pondělí ráno.',
      posts_week: 'týden', posts_count: 'postů', post_media: 'Příloha',
      post_media_only: '[Příspěvek s médiem]', post_open: 'Otevřít na Mastodonu',
      post_more: 'zobrazit více', post_riser: 'Skokan', profile_title: 'Otevřít profil',
      head_hashtags: 'Hashtagy', hashtags_empty: 'Žádné hashtagy v zobrazených postech.'
    },
    en: {
      brand_prefix: 'Sloník', brand_domain: 'CZ | SK Mastodon catalog', title_doc: 'Sloník.online — CZ | SK Mastodon catalog',
      claim: 'Discover Czech and Slovak users on Mastodon',
      count_of: 'of', count_sources: 'sources',
      nav_platform: 'Platform', nav_charts: 'Charts', nav_risers: 'Weekly risers', nav_new: 'New',
      nav_all: 'All', nav_top10_foll: 'Top 10 followed', nav_top10_active: 'Top 10 active',
      nav_top50_foll: 'Top 50 followed', nav_top50_active: 'Top 50 active',
      nav_risers_foll: 'In followers', nav_risers_active: 'In activity', nav_recent: 'Recently added',
      filters_toggle: 'Filters', menu_show: 'Menu', menu_hide: 'Close', nav_views: 'Sections',
      nav_slices: 'Charts', head_topic_byaccount: 'Topic (by account)',
      search_label: 'Search', search_ph: 'Name or handle…',
      sort_label: 'Sort', sort_name: 'Alphabetically', sort_followers: 'Most followers',
      sort_posts: 'Most active', sort_added: 'Recently added',
      head_topic: 'Topic', head_type: 'Account type', head_language: 'Language', head_tag: 'Tag',
      tag_ph: 'Filter by tag…', reset: 'Clear filters',
      loading: 'Loading catalog…', empty_title: 'No source matches the filters.',
      empty_hint: 'Try loosening one of the filters.', empty_reset: 'Reset filters',
      load_error: 'Failed to load catalog data.',
      footer_indexed: 'Search last indexed',
      footer_updated: 'Catalog last updated',
      footer_owner: 'Are you the owner and want it removed from the catalog? Write to',
      fam_sport: 'Sports', fam_news: 'News', fam_culture: 'Culture', fam_science_tech: 'Science & tech',
      fam_lifestyle: 'Lifestyle', fam_business: 'Business', fam_humor: 'Humor', fam_government: 'Government',
      type_person: 'Person', type_media: 'Media', type_institution: 'Organization',
      type_institution_formal: 'Institution', type_institution_filter: 'Institution/Organization',
      type_team: 'Team', type_other: 'Other',
      lang_cs: 'Czech', lang_sk: 'Slovak', lang_en: 'English',
      stat_followers: 'followers', stat_posts_week: 'posts/week', stat_language: 'language',
      modal_sources: 'Original profiles', modal_open: 'Open profile', modal_follow: 'Follow',
      modal_follow_title: 'Opens the profile where you can follow from your own Mastodon instance', modal_close: 'Close',
      hover_source: 'Source: ', card_detail: 'Detail of ',
      slice_platform: 'Sources on ', slice_recent_pre: 'Added in the last ',
      slice_recent_post: ' days', slice_top_pre: 'Top ', slice_top_post: ' (filters except topic are off)',
      top_phrase_followers: 'by followers', top_phrase_active: 'by activity',
      top_phrase_gain_followers: 'by follower growth', top_phrase_gain_activity: 'by activity growth',
      view_accounts: 'Accounts', view_posts: 'Posts', view_about: 'About Sloník', view_search: 'Search', view_instance: 'Instances', view_links: 'Links',
      links_nav_title: 'Links',
      links_nav_desc: 'A curated set of quality articles and guides about Mastodon and the fediverse — Czech and English. Filter by type and language.',
      links_head_type: 'Type', links_count: 'links',
      ltype_explainer: 'Explainers', ltype_navod: 'Guides', ltype_provozovatel: 'For instance admins', ltype_kontext: 'Context',
      lfresh_undated: 'undated', lfresh_current: 'kept current', links_zero: 'No link matches the filters.',
      accounts_nav_title: 'Accounts',
      accounts_nav_desc: 'A catalog of Czech and Slovak accounts on Mastodon. Filter by topic, type, language and tags, search by name or handle, and sort by followers or activity. Click an account for details.',
      posts_nav_title: 'Posts',
      posts_nav_desc: 'The best posts from Czech and Slovak accounts over the past week. Switch charts (Top 10/50, weekly risers), filter by topic, text and hashtags, and sort by boosts, favourites or date.',
      instance_nav_title: 'Instances',
      instance_nav_desc: 'Czech & Slovak Mastodon instances — where to create an account and who you will find there. Each shows size, activity, registration status and how many accounts from this catalog live there. Sorted by size.',
      instance_loading: 'Loading instances…', instance_unavail: 'Instance list is not available yet.',
      instance_count: 'instances', instance_reg_open: 'Registrations open',
      instance_reg_approval: 'Registrations with approval', instance_reg_closed: 'Registrations closed',
      instance_join: 'Create account', instance_open: 'open',
      instance_users: 'users', instance_active: 'active/mo', instance_posts: 'posts',
      instance_catalog: 'in catalog',
      instance_sec_czsk: 'Czech & Slovak instances',
      instance_sec_other: 'Other instances with Czech/Slovak accounts',
      instance_sec_small: 'Small / personal instances',
      instance_search_ph: 'Name or domain…',
      isort_users: 'Most users', isort_active: 'Most active',
      isort_catalog: 'Most catalog accounts', isort_posts: 'Most posts',
      instance_region_head: 'Topic',
      irank_activity: 'Instance activity', irank_ratio: 'By ratio', irank_volume: 'By volume',
      irank_ratio_note: 'by share of active users', irank_volume_note: 'by total number of posts',
      ssort_relevance: 'By relevance',
      search_tagline: 'Searches accounts and posts across the Czech & Slovak Mastodon — diacritics-insensitive, no login needed.',
      search_tip: 'Tip: multiple words must all appear; wrap an exact phrase in quotes ("…"), exclude a word with a minus (-word).',
      search_ph_view: 'Search accounts and posts…', search_unit_accounts: 'accounts', search_unit_posts: 'posts',
      search_sec_accounts: 'Accounts', search_sec_posts: 'Posts', search_loading: 'Loading index…',
      search_hint: 'type a query', search_zero: 'Nothing found. Try other / broader words.',
      search_unavail: 'Search index is not available yet.', search_open: 'open on Mastodon',
      search_posts_active: 'posts (30 days)', search_followers: 'followers',
      search_nav_title: 'Search',
      search_nav_desc: 'Searches accounts and posts of the Czech & Slovak Mastodon. Case- and diacritics-insensitive (type "bouzkova", finds "Bouzková"), across all instances at once, no login. Results cover the last few weeks.',
      about_title: 'About Sloník',
      about_menu_about: 'About Sloník', about_menu_howto: 'How to use', about_menu_other: 'Other',
      about_menu_other_desc: 'And finally, a few closing notes — FAQ, the tech behind it, about the author, and how to support the project.',
      about_menu_about_desc: 'Sloník is a catalog of Czech and Slovak users of Mastodon. It helps you find interesting people, media and institutions from our region — across all servers (instances), no matter where their account lives.',
      about_menu_howto_desc: 'A few tips on how to get the most out of what Sloník.online offers for working with:',
      about_nav_about: 'About', about_nav_search: 'Search', about_nav_instance: 'Instances',
      about_nav_accounts: 'Accounts', about_nav_posts: 'Posts', about_nav_links_howto: 'Links',
      about_nav_tech: 'Technical details', about_nav_author: 'About the author', about_nav_faq: 'FAQ',
      prisers_ratio: 'By ratio', prisers_abs: 'By reach',
      label_bot: 'Bot', label_bot_title: 'Automated account (bot)',
      psort_engagement: 'Most boosts + favs', psort_reblogs: 'Most boosts',
      psort_favourites: 'Most favs', psort_date: 'Newest', psort_date_asc: 'Oldest first',
      posts_loading: 'Loading posts…', posts_empty: 'No post matches the filters.',
      posts_unavailable: 'Posts are available every week on Monday morning.',
      posts_week: 'Week', posts_count: 'posts', post_media: 'Attachment',
      post_media_only: '[Post with media]', post_open: 'Open on Mastodon',
      post_more: 'show more', post_riser: 'Riser', profile_title: 'Open profile',
      head_hashtags: 'Hashtags', hashtags_empty: 'No hashtags in shown posts.'
    }
  };

  function t(key) {
    var s = STRINGS[lang] && STRINGS[lang][key];
    return s != null ? s : (STRINGS.cs[key] != null ? STRINGS.cs[key] : key);
  }

  // Platform names — značky, nepřekládají se.
  var PLATFORM_LABELS = {
    twitter: 'X', threads: 'Threads', bluesky: 'Bluesky', facebook: 'Facebook',
    instagram: 'Instagram', youtube: 'YouTube', rss: 'RSS'
  };
  function platformLabel(p) { return PLATFORM_LABELS[p] || p; }
  function familyLabel(f) { return t('fam_' + f); }
  function escapeHtml(s) {
    return (s || '').replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }
  function langLabel(l) { return t('lang_' + l); }

  // Typ "institution" se pojmenuje podle oblasti — vláda/kultura „Instituce",
  // jinde „Organizace". Týmy mají vlastní typ.
  var INSTITUTION_FORMAL_FAMILIES = { government: 1, culture: 1 };
  function typeLabel(rec) {
    if (rec.type === 'institution') {
      return INSTITUTION_FORMAL_FAMILIES[rec.family] ? t('type_institution_formal') : t('type_institution');
    }
    return t('type_' + rec.type);
  }

  // Štítek filtru "institution" se přizpůsobí zvolené oblasti (1 oblast → varianta).
  function updateInstitutionFilterLabel() {
    if (!institutionBtnEl) return;
    var label = t('type_institution_filter');
    if (filters.family.size === 1) {
      var fam = filters.family.values().next().value;
      label = INSTITUTION_FORMAL_FAMILIES[fam] ? t('type_institution_formal') : t('type_institution');
    }
    institutionBtnEl.textContent = label;
  }

  // Jazyk z ?lang= (sdílitelné) → localStorage → default 'cs'. Bez detekce prohlížeče.
  function initLang() {
    var fromUrl = new URLSearchParams(location.search).get('lang');
    var stored = null;
    try { stored = localStorage.getItem('zbnw_lang'); } catch (e) { /* ignore */ }
    var pick = fromUrl || stored || 'cs';
    lang = LANGS.indexOf(pick) !== -1 ? pick : 'cs';
    document.documentElement.lang = lang;
  }

  // Přeloží statické prvky ([data-i18n] textContent, [data-i18n-ph] placeholder)
  // + titulek dokumentu. Dynamický obsah (karty/modal) řeší render() přes t().
  function applyI18n() {
    document.title = t('title_doc');
    document.documentElement.lang = lang;
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      el.textContent = t(el.getAttribute('data-i18n'));
    });
    document.querySelectorAll('[data-i18n-ph]').forEach(function (el) {
      el.setAttribute('placeholder', t(el.getAttribute('data-i18n-ph')));
    });
    // Bohatý obsah (O Sloníkovi) — bloky cs/en, zobraz jen aktuální jazyk.
    document.querySelectorAll('[data-lang-block]').forEach(function (el) {
      el.hidden = el.getAttribute('data-lang-block') !== lang;
    });
    updateLangSwitchUI();
    updateSidebarToggleLabel();
    updateFamilyHeading();
  }

  function setLang(next) {
    if (LANGS.indexOf(next) === -1 || next === lang) return;
    lang = next;
    try { localStorage.setItem('zbnw_lang', lang); } catch (e) { /* ignore */ }
    // ?lang v query (mimo hash filtrů) — sdílitelné, přežije refresh
    var params = new URLSearchParams(location.search);
    if (lang === 'cs') { params.delete('lang'); } else { params.set('lang', lang); }
    var qs = params.toString();
    history.replaceState(null, '', location.pathname + (qs ? '?' + qs : '') + location.hash);
    applyI18n();
    render();
    applyView();   // zachová aktuální pohled (Posty/O Sloníku) + přegeneruje meta (týden) v novém jazyce
    renderUpdatedRelative();
  }

  function bindLangSwitch() {
    var sw = document.getElementById('lang-switch');
    if (!sw) return;
    sw.querySelectorAll('button[data-lang]').forEach(function (btn) {
      btn.addEventListener('click', function () { setLang(btn.getAttribute('data-lang')); });
    });
  }

  function updateLangSwitchUI() {
    var sw = document.getElementById('lang-switch');
    if (!sw) return;
    sw.querySelectorAll('button[data-lang]').forEach(function (btn) {
      btn.classList.toggle('is-active', btn.getAttribute('data-lang') === lang);
    });
  }

  // ========================================================
  // Pohled: přepínač Účty | Posty
  // ========================================================
  // Navigace je na DVOU místech: navbar (desktop) + mobilní drawer („Pohledy").
  // Vážeme/zvýrazňujeme proto VŠECHNA [data-view] tlačítka napříč dokumentem.
  function bindViewSwitch() {
    document.querySelectorAll('[data-view]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        setView(btn.getAttribute('data-view'));
        if (sidebarEl) sidebarEl.classList.remove('open');   // v draweru: po volbě zavři menu
        if (sidebarToggleEl) sidebarToggleEl.setAttribute('aria-expanded', 'false');
        updateSidebarToggleLabel();
      });
    });
  }

  function setView(next) {
    if (['ucty', 'posty', 'instance', 'search', 'about', 'odkazy'].indexOf(next) === -1) return;
    if (next === view) return;
    view = next;
    applyView();
    writeHash();
  }

  // Promítne aktuální `view` do DOM (skryje/zobrazí sekce, načte posty/search lazy).
  function applyView() {
    var isPosts = view === 'posty';
    var isAbout = view === 'about';
    var isSearch = view === 'search';
    var isInstance = view === 'instance';
    var isAccounts = view === 'ucty';
    var isLinks = view === 'odkazy';
    if (accountsViewEl) accountsViewEl.hidden = !isAccounts;
    if (postsViewEl) postsViewEl.hidden = !isPosts;
    if (aboutViewEl) aboutViewEl.hidden = !isAbout;
    if (searchViewEl) searchViewEl.hidden = !isSearch;
    if (instanceViewEl) instanceViewEl.hidden = !isInstance;
    if (linksViewEl) linksViewEl.hidden = !isLinks;
    if (sidebarEl) sidebarEl.hidden = false;   // sidebar zůstává ve všech pohledech
    document.body.classList.toggle('view-posts', isPosts);
    document.body.classList.toggle('view-about', isAbout);
    document.body.classList.toggle('view-search', isSearch);
    document.body.classList.toggle('view-instance', isInstance);
    if (tabsEl) tabsEl.hidden = !isAccounts;        // řezy účtů jen v Účtech
    if (postsTabsEl) postsTabsEl.hidden = !isPosts; // řezy postů (Vše/Top10/Top50/Skokani)
    if (instanceTabsEl) instanceTabsEl.hidden = !isInstance; // řezy instancí
    if (searchTabsEl) searchTabsEl.hidden = !isSearch;       // řezy výsledků hledání
    if (linksTabsEl) linksTabsEl.hidden = !isLinks;          // lišta s počtem odkazů
    // Účtové filtry (typ/jazyk/tag/řazení) jen v Účtech.
    document.querySelectorAll(
      '.filter-group[data-filter="type"], .filter-group[data-filter="language"],' +
      '.filter-group[data-filter="tag"], .filter-sort:not(.filter-sort-posts):not(.filter-sort-instance):not(.filter-sort-search)'
    ).forEach(function (el) { el.hidden = !isAccounts; });
    // Fulltext (malé pole) + reset: jen v Účtech a Postech.
    document.querySelectorAll(
      '.filter-search:not(.filter-search-instance), #reset-filters'
    ).forEach(function (el) { el.hidden = !(isAccounts || isPosts); });
    // Oblast (rodina) + Hashtagy: Účty, Posty i Vyhledávání.
    document.querySelectorAll('.filter-group[data-filter="family"]')
      .forEach(function (el) { el.hidden = !(isAccounts || isPosts || isSearch); });
    if (postsSortWrapEl) postsSortWrapEl.hidden = !isPosts;
    if (postHashtagsGroupEl) postHashtagsGroupEl.hidden = !(isPosts || isSearch);
    // Instanční filtry (Vyhledat / Řadit / Oblast) jen v Instancích.
    [instanceSearchWrapEl, instanceSortWrapEl, instanceRegionGroupEl].forEach(function (el) {
      if (el) el.hidden = !isInstance;
    });
    // Vyhledávací řazení jen ve Vyhledávání.
    if (searchSortWrapEl) searchSortWrapEl.hidden = !isSearch;
    // Filtry Odkazů (Typ / Jazyk) jen v Odkazech.
    document.querySelectorAll('.filter-group-links').forEach(function (el) { el.hidden = !isLinks; });
    if (accountsNavEl) accountsNavEl.hidden = !isAccounts; // levý panel Účty
    if (postsNavEl) postsNavEl.hidden = !isPosts;          // levý panel Posty
    if (aboutNavEl) aboutNavEl.hidden = !isAbout;
    if (searchNavEl) searchNavEl.hidden = !isSearch;      // levý panel Vyhledávání
    if (instanceNavEl) instanceNavEl.hidden = !isInstance; // levý panel Instance
    if (linksNavEl) linksNavEl.hidden = !isLinks;          // levý panel Odkazy
    // Nadpis „Rychlé filtry" v draweru — skrýt tam, kde žádné řezy nejsou (O Sloníku).
    if (slicesHeadingEl) slicesHeadingEl.hidden = isAbout;
    updateViewSwitchUI();
    updateFamilyHeading();
    if (isAbout) applyAboutSection();
    if (isPosts) {
      updatePostsTabsUI();
      ensurePostsLoaded();
      renderPosts();
    }
    if (isSearch) {
      updateSearchTabsUI();
      // Index (~MB) NEnačítáme na landing — až při dotazu/focusu (viz bindSearchView).
      // Výjimka: deep-link s dotazem (sq=) → načti hned.
      if (searchQEl && searchQEl.value.trim()) {
        ensureSearchLoaded().then(function () { renderSearch(); });
      } else {
        renderSearch();   // jen landing (logo + pole), bez fetche
        if (searchQEl) setTimeout(function () { searchQEl.focus(); }, 0);
      }
    }
    if (isInstance) {
      updateInstanceTabsUI();
      ensureInstancesLoaded().then(function () { buildInstanceCatChips(); renderInstances(); });
    }
    if (isLinks) renderLinks();
  }

  // Zobrazí vybranou sekci „O Sloníkovi" a zvýrazní položku menu.
  function applyAboutSection() {
    document.querySelectorAll('#about-view [data-about-section]').forEach(function (el) {
      el.hidden = el.getAttribute('data-about-section') !== aboutSection;
    });
    if (aboutNavEl) {
      aboutNavEl.querySelectorAll('button[data-about]').forEach(function (btn) {
        btn.classList.toggle('active', btn.getAttribute('data-about') === aboutSection);
      });
    }
  }

  function bindAboutNav() {
    if (!aboutNavEl) return;
    aboutNavEl.querySelectorAll('button[data-about]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        aboutSection = btn.getAttribute('data-about');
        applyAboutSection();
        writeHash();
      });
    });
  }

  // ========================================================
  // Vyhledávání (účty + posty) — index search.json / users.json
  // ========================================================
  function fold(s) { return (s || '').normalize('NFKD').replace(/\p{Mn}/gu, '').toLowerCase().replace(/\s+/g, ' ').trim(); }

  function ensureSearchLoaded() {
    if (searchState === 'loaded' || searchState === 'loading') {
      return searchPromise || Promise.resolve();
    }
    searchState = 'loading';
    if (searchMetaEl) searchMetaEl.textContent = t('search_loading');
    searchPromise = Promise.all([
      fetch('search.json', { cache: 'no-cache' }).then(function (r) { return r.ok ? r.json() : { posts: [] }; }),
      fetch('users.json', { cache: 'no-cache' }).then(function (r) { return r.ok ? r.json() : { users: [] }; })
    ]).then(function (a) {
      searchPosts = (a[0] && a[0].posts) || [];
      searchUsers = (a[1] && a[1].users) || [];
      hydrateSearchPosts();   // dopočítej content_plain/folded + engagement z content_html
      computeSearchRisers();
      searchState = 'loaded';
    }).catch(function () {
      searchState = 'error';
      if (searchMetaEl) searchMetaEl.textContent = t('search_unavail');
    });
    return searchPromise;
  }

  // HTML → čistý text (rychlý regex, ne DOMParser) pro hledání/zkrácení. Pro
  // ZOBRAZENÍ se používá content_html (sanitizePostHtml), tohle stačí na fold + délku.
  function htmlToText(h) {
    return (h || '')
      .replace(/<br\s*\/?>/gi, ' ').replace(/<\/(p|div|li)>/gi, ' ')
      .replace(/<[^>]+>/g, '')
      .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"').replace(/&#0?39;/g, "'").replace(/&nbsp;/g, ' ')
      .replace(/\s+/g, ' ').trim();
  }

  // Index drží jen content_html (menší). Tady dopočítáme to, co frontend potřebuje:
  // content_plain (zobrazení/zkrácení), content_folded (hledání), engagement.
  function hydrateSearchPosts() {
    searchPosts.forEach(function (p) {
      if (p.content_html) {                              // slim index → odvoď z HTML
        p.content_plain = htmlToText(p.content_html);
        p.content_folded = fold(p.content_plain + ' ' + (p.account_acct || '') + ' ' + (p.account_display_name || ''));
      } else {                                           // starý/přechodný záznam → ponech, co přišlo
        if (p.content_plain == null) p.content_plain = '';
        if (p.content_folded == null) {
          p.content_folded = fold(p.content_plain + ' ' + (p.account_acct || '') + ' ' + (p.account_display_name || ''));
        }
      }
      if (p.engagement == null) p.engagement = (p.reblogs_count || 0) + (p.favourites_count || 0);
    });
  }

  // Skokani pro vyhledávání — stejná definice jako týdenní risers v Postech:
  // riser_score = engagement − průměr účtu; riser_ratio = engagement / průměr;
  // účty s < 3 posty v indexu vyřazeny. Počítá se z celého search indexu (jednou).
  function computeSearchRisers() {
    var sum = {}, cnt = {};
    searchPosts.forEach(function (p) {
      var a = p.account_acct; sum[a] = (sum[a] || 0) + (p.engagement || 0); cnt[a] = (cnt[a] || 0) + 1;
    });
    searchPosts.forEach(function (p) {
      var a = p.account_acct, n = cnt[a] || 0, avg = n ? sum[a] / n : 0;
      if (n >= 3 && avg > 0) {
        p.riser_ratio = (p.engagement || 0) / avg;
        p.riser_score = (p.engagement || 0) - avg;
      } else { p.riser_ratio = null; p.riser_score = null; }
    });
  }

  // Rozparsuje dotaz na tokeny: text v "uvozovkách" = jedna fráze (i s mezerami),
  // ostatní slova zvlášť, „-slovo" / -"fráze" = vyloučení (neg). Vše složené
  // (NFKD, bez diakritiky, lowercase). Vrací [{ t, neg }].
  function parseQueryTokens(raw) {
    var tokens = [];
    // Volitelné „-" před tokenem; uvozovky ASCII " i typografické „ " ".
    var re = /(-?)(?:["„“”]([^"„“”]+)["„“”]|(\S+))/g, m;
    while ((m = re.exec(raw || '')) !== null) {
      var t = fold(m[2] != null ? m[2] : m[3]).trim().replace(/\s+/g, ' ');
      if (t) tokens.push({ t: t, neg: m[1] === '-' });
    }
    return tokens;
  }

  // AND: záznam projde, jen když obsahuje VŠECHNA kladná slova/fráze a ŽÁDNÉ
  // vyloučené (-). Dotaz jen z vyloučení (bez kladného) → nic (nesmyslné).
  function searchRank(list, tokens, field) {
    field = field || 'f';                    // účty: 'f' · posty: 'content_folded'
    var pos = tokens.filter(function (x) { return !x.neg; });
    var neg = tokens.filter(function (x) { return x.neg; });
    var hits = [];
    if (!pos.length) return hits;
    for (var i = 0; i < list.length; i++) {
      var f = list[i][field];
      if (!f) continue;
      var ok = true;
      for (var k = 0; k < pos.length; k++) { if (f.indexOf(pos[k].t) === -1) { ok = false; break; } }
      if (ok) { for (var n = 0; n < neg.length; n++) { if (f.indexOf(neg[n].t) !== -1) { ok = false; break; } } }
      if (ok) hits.push({ x: list[i], m: pos.length });
    }
    return hits;
  }

  // Účet z users.json → karta. Když je v katalogu, použij plný záznam (modal
  // funguje stejně jako v Účtech); jinak minimální „externí" záznam.
  function searchAccountCard(u) {
    // Katalogový účet (i neaktivní) → plná karta + detail (modal). Jinak autor
    // mimo katalog → minimální karta s odkazem na profil.
    var full = catalogById[u.a];
    if (full) return buildCard(full);
    return buildCard({
      id: u.a, display_name: u.n || u.a, avatar: u.av,
      followers: u.fo || 0, posts_week: null,
      profile_url: 'https://' + u.i + '/@' + u.a.split('@')[0], _external: true
    });
  }

  function searchSection(label, total, shown) {
    var h = document.createElement('h2');
    h.className = 's-sec';
    h.textContent = label + ' ';
    var s = document.createElement('span');
    s.textContent = total + (shown ? ', ' + shown : '');
    h.appendChild(s);
    return h;
  }

  var SEARCH_MAX_USERS = 18, SEARCH_MAX_POSTS = 100;

  function renderSearch() {
    if (!searchResultsEl) return;
    // Landing logo/claim schovej, jakmile je zadaný dotaz (jako Google výsledky).
    if (searchViewEl) searchViewEl.classList.toggle('has-query', !!(searchQEl && searchQEl.value.trim()));
    if (searchState !== 'loaded') {
      if (searchState === 'error') searchMetaEl.textContent = t('search_unavail');
      return;
    }
    var tokens = parseQueryTokens(searchQEl.value);
    if (tokens.length === 0) {
      searchResultsEl.innerHTML = '';
      if (postHashtagChipsEl) renderPostHashtagUI([]);   // prázdná nabídka hashtagů
      searchMetaEl.textContent = searchUsers.length + ' ' + t('search_unit_accounts') + ' · '
        + searchPosts.length + ' ' + t('search_unit_posts');
      return;
    }

    // PREFIX MÓD (1–2 znaky, jedno slovo): jen ÚČTY, shoda od ZAČÁTKU jména/handle.
    // (Krátký dotaz přes substring napříč posty je moc široký.) Od 3 znaků plné hledání.
    var qfold = fold(searchQEl.value);
    if (qfold.length >= 1 && qfold.length <= 2 && qfold.indexOf(' ') === -1) {
      var pre = searchUsers.filter(function (u) {
        if (filters.family.size && !filters.family.has(u.ob)) return false;
        var name = fold(u.n || '');
        var handle = fold((u.a || '').split('@')[0]);
        return name.indexOf(qfold) === 0 || handle.indexOf(qfold) === 0;
      }).sort(function (a, b) { return (b.fo || b.np || 0) - (a.fo || a.np || 0); });

      if (postHashtagChipsEl) renderPostHashtagUI([]);
      searchMetaEl.textContent = pre.length + ' ' + t('search_unit_accounts');
      searchResultsEl.innerHTML = '';
      if (pre.length) {
        searchResultsEl.appendChild(searchSection(t('search_sec_accounts'), pre.length));
        var pug = document.createElement('div');
        pug.className = 'cards-grid';
        pre.slice(0, SEARCH_MAX_USERS).forEach(function (u) { pug.appendChild(searchAccountCard(u)); });
        searchResultsEl.appendChild(pug);
      } else {
        var pz = document.createElement('p');
        pz.className = 's-empty'; pz.textContent = t('search_zero');
        searchResultsEl.appendChild(pz);
      }
      return;
    }

    // Účty: shoda + filtr Oblast (rodina je jen u katalogových účtů).
    var uHits = searchRank(searchUsers, tokens).filter(function (h) {
      return !filters.family.size || filters.family.has(h.x.ob);
    });
    uHits.sort(function (a, b) {
      if (b.m !== a.m) return b.m - a.m;
      if (!!b.x.cat !== !!a.x.cat) return (b.x.cat ? 1 : 0) - (a.x.cat ? 1 : 0);
      return (b.x.fo || b.x.np || 0) - (a.x.fo || a.x.np || 0);
    });

    // Posty: shoda + filtr Oblast (account_family).
    var pAll = searchRank(searchPosts, tokens, 'content_folded').filter(function (h) {
      return !filters.family.size || filters.family.has(h.x.account_family);
    });
    // Nabídku hashtagů počítej z postů PŘED hashtag filtrem (jako na Posty).
    renderPostHashtagUI(pAll.map(function (h) { return h.x; }));
    var pHits = pAll.filter(function (h) { return matchesPostHashtag(h.x); });

    // Žebříčky Skokani (Poměrem/Dosahem) — stejná logika jako Posty: řazení dle
    // riser metriky; jinak řazení dle volby + Top N.
    var riser = (searchTab === 'risers_ratio') ? 'riser_ratio'
              : (searchTab === 'risers_abs') ? 'riser_score' : null;
    var postLimit;
    if (riser) {
      pHits = pHits.filter(function (h) { return h.x[riser] != null; })
                   .sort(function (a, b) { return b.x[riser] - a.x[riser]; });
      postLimit = SEARCH_MAX_POSTS;
    } else {
      sortSearchPosts(pHits);
      postLimit = searchTab === '10' ? 10 : searchTab === '50' ? 50 : SEARCH_MAX_POSTS;
    }
    searchMetaEl.textContent = uHits.length + ' ' + t('search_unit_accounts') + ' · '
      + pHits.length + ' ' + t('search_unit_posts');

    searchResultsEl.innerHTML = '';
    if (uHits.length) {
      searchResultsEl.appendChild(searchSection(t('search_sec_accounts'), uHits.length));
      var ug = document.createElement('div');
      ug.className = 'cards-grid';
      uHits.slice(0, SEARCH_MAX_USERS).forEach(function (h) { ug.appendChild(searchAccountCard(h.x)); });
      searchResultsEl.appendChild(ug);
    }
    if (pHits.length) {
      searchResultsEl.appendChild(searchSection(t('search_sec_posts'), pHits.length,
        pHits.length > postLimit ? postLimit : 0));
      var pg = document.createElement('div');
      pg.className = 'cards-grid posts-grid';
      pHits.slice(0, postLimit).forEach(function (h) { pg.appendChild(buildPostCard(h.x)); });
      searchResultsEl.appendChild(pg);
    }
    if (!uHits.length && !pHits.length) {
      var e = document.createElement('p');
      e.className = 's-empty';
      e.textContent = t('search_zero');
      searchResultsEl.appendChild(e);
    }
  }

  // Řazení postů ve výsledcích hledání podle volby v levém menu.
  function sortSearchPosts(pHits) {
    if (searchSort === 'date') {
      pHits.sort(function (a, b) { return (b.x.created_at || '').localeCompare(a.x.created_at || ''); });
    } else if (searchSort === 'engagement' || searchSort === 'reblogs' || searchSort === 'favourites') {
      var key = searchSort === 'engagement' ? 'engagement' : searchSort === 'reblogs' ? 'reblogs_count' : 'favourites_count';
      pHits.sort(function (a, b) { return (b.x[key] || 0) - (a.x[key] || 0); });
    } else { // relevance (default): shoda, pak datum
      pHits.sort(function (a, b) { return b.m !== a.m ? b.m - a.m : (b.x.created_at || '').localeCompare(a.x.created_at || ''); });
    }
  }

  function updateSearchTabsUI() {
    if (!searchTabsEl) return;
    searchTabsEl.querySelectorAll('.tab[data-stab]').forEach(function (tab) {
      tab.classList.toggle('is-active', tab.getAttribute('data-stab') === searchTab);
    });
  }

  var searchTimer = null;
  function bindSearchView() {
    if (searchQEl) {
      // Focus = uživatel hodlá hledat → začni stahovat index na pozadí (zrychlejší 1. výsledek).
      searchQEl.addEventListener('focus', function () {
        ensureSearchLoaded().then(function () { renderSearch(); });
      });
      searchQEl.addEventListener('input', function () {
        clearTimeout(searchTimer);
        searchTimer = setTimeout(function () {
          ensureSearchLoaded().then(function () { renderSearch(); });
          writeHash();
        }, 120);
      });
    }
    if (searchTabsEl) {
      searchTabsEl.querySelectorAll('.tab[data-stab]').forEach(function (tab) {
        tab.addEventListener('click', function () {
          searchTab = tab.getAttribute('data-stab');
          updateSearchTabsUI();
          renderSearch();
          writeHash();
        });
      });
    }
    if (searchSortEl) {
      searchSortEl.addEventListener('change', function () {
        searchSort = searchSortEl.value;
        renderSearch();
      });
    }
  }

  // ========================================================
  // Pohled: Instance (adresář CZ/SK instancí z instances.json)
  // ========================================================
  function ensureInstancesLoaded() {
    if (instanceState === 'loaded' || instanceState === 'loading') {
      return instancePromise || Promise.resolve();
    }
    instanceState = 'loading';
    if (instanceMetaEl) instanceMetaEl.textContent = t('instance_loading');
    instancePromise = fetch('instances.json', { cache: 'no-cache' })
      .then(function (r) { return r.ok ? r.json() : { instances: [] }; })
      .then(function (d) { instanceList = (d && d.instances) || []; instanceState = 'loaded'; })
      .catch(function () { instanceState = 'error'; });
    return instancePromise;
  }

  function instanceAvatar(i) {
    if (i.thumbnail) {
      var img = document.createElement('img');
      img.className = 'inst-logo'; img.src = i.thumbnail; img.alt = ''; img.loading = 'lazy';
      img.onerror = function () {
        var fb = instanceFallback(i); img.replaceWith(fb);
      };
      return img;
    }
    return instanceFallback(i);
  }
  function instanceFallback(i) {
    var s = document.createElement('span');
    s.className = 'inst-logo inst-logo-fb';
    s.textContent = (i.host || '?').charAt(0).toUpperCase();
    return s;
  }

  function buildInstanceCard(i) {
    var card = document.createElement('article');
    card.className = 'inst-card';

    var head = document.createElement('div');
    head.className = 'inst-head';
    head.appendChild(instanceAvatar(i));
    var hb = document.createElement('div');
    hb.className = 'inst-headbody';
    var title = document.createElement('div'); title.className = 'inst-title'; title.textContent = i.title || i.host;
    var host = document.createElement('div'); host.className = 'inst-host'; host.textContent = i.host;
    hb.appendChild(title); hb.appendChild(host);
    head.appendChild(hb);
    if (i.registrations) {
      var reg = document.createElement('span');
      reg.className = 'inst-reg inst-reg-' + i.registrations;
      reg.textContent = t('instance_reg_' + i.registrations);
      head.appendChild(reg);
    }
    card.appendChild(head);

    if (i.description) {
      var d = document.createElement('p'); d.className = 'inst-desc'; d.textContent = i.description;
      card.appendChild(d);
    }

    var stats = document.createElement('div');
    stats.className = 'inst-stats';
    if (i.users != null) stats.appendChild(instStat(formatNumber(i.users), t('instance_users')));
    if (i.active_month != null) stats.appendChild(instStat(formatNumber(i.active_month), t('instance_active')));
    if (i.statuses != null) stats.appendChild(instStat(formatNumber(i.statuses), t('instance_posts')));
    card.appendChild(stats);

    var foot = document.createElement('div');
    foot.className = 'inst-foot';
    var catn = document.createElement('span');
    catn.className = 'inst-cat';
    catn.textContent = '🐘 ' + t('instance_catalog') + ': ' + (i.catalog_count || 0);
    foot.appendChild(catn);
    var link = document.createElement('a');
    if (i.registrations === 'open' || i.registrations === 'approval') {
      link.className = 'inst-join';
      link.href = 'https://' + i.host + '/auth/sign_up';
      link.textContent = t('instance_join');
    } else {
      link.className = 'inst-open';
      link.style.marginLeft = 'auto';
      link.href = 'https://' + i.host + '/about';
      link.textContent = '↗ ' + t('instance_open');
    }
    link.target = '_blank'; link.rel = 'noopener';
    foot.appendChild(link);
    card.appendChild(foot);
    return card;
  }

  function instStat(value, label) {
    var s = document.createElement('span');
    var v = document.createElement('strong'); v.textContent = value;
    s.appendChild(v); s.appendChild(document.createTextNode(' ' + label));
    return s;
  }

  var INSTANCE_SORT_KEY = { users: 'users', active: 'active_month', catalog: 'catalog_count', posts: 'statuses' };
  var INSTANCE_RANK_TOP = 10;    // žebříčky Poměrem/Objemem ukazují top N
  var INSTANCE_SMALL_USERS = 10; // pod tolik uživatelů → „Malé / osobní" (sekce i volba ve filtru)

  // Poměr = podíl měsíčně aktivních uživatelů k celkovému počtu (živost komunity).
  function instRatio(i) { return (i.users > 0) ? (i.active_month || 0) / i.users : 0; }
  // Objem = celkový počet příspěvků na instanci (kvantitativní rozsah obsahu).
  function instVolume(i) { return i.statuses || 0; }

  // Číselník zaměření instancí = kategorie joinmastodon.org (kód → CZ/EN popisek).
  var INSTANCE_CAT_LABELS = {
    general: { cs: 'Obecná', en: 'General' }, academia: { cs: 'Akademická', en: 'Academia' },
    activism: { cs: 'Aktivismus', en: 'Activism' }, art: { cs: 'Umění', en: 'Art' },
    books: { cs: 'Knihy', en: 'Books' }, food: { cs: 'Jídlo', en: 'Food' },
    furry: { cs: 'Furry', en: 'Furry' }, games: { cs: 'Hry', en: 'Games' },
    journalism: { cs: 'Média', en: 'Journalism' }, lgbt: { cs: 'LGBT+', en: 'LGBT+' },
    music: { cs: 'Hudba', en: 'Music' }, regional: { cs: 'Region', en: 'Regional' },
    tech: { cs: 'Technologie', en: 'Tech' },
    __small: { cs: 'Malá / Osobní', en: 'Small / personal' }   // pseudo-kategorie dle velikosti
  };
  function catLabel(slug) {
    var l = INSTANCE_CAT_LABELS[slug];
    return l ? (l[lang] || l.cs) : slug;
  }

  // Filtrace: fulltext nad doménou/názvem/popisem + zvolené oblasti (kategorie).
  function filteredInstances() {
    var tokens = fold(instanceQuery).split(/\s+/).filter(Boolean);
    return instanceList.filter(function (i) {
      if (instanceCats.size) {
        var hit = false;
        // „Malá / Osobní" = syntetická volba podle velikosti (ne z dat).
        if (instanceCats.has('__small') && (i.users || 0) < INSTANCE_SMALL_USERS) hit = true;
        if (!hit) hit = (i.categories || []).some(function (c) { return instanceCats.has(c); });
        if (!hit) return false;
      }
      if (!tokens.length) return true;
      var f = fold((i.host || '') + ' ' + (i.title || '') + ' ' + (i.description || ''));
      return tokens.every(function (tok) { return f.indexOf(tok) >= 0; });
    });
  }

  // Postaví chipy oblastí: tematické kategorie z dat (s počty) + volba „Malá / Osobní"
  // (syntetická, dle velikosti). Bez kategorií i bez malých → skupinu „Oblast" schovej.
  function buildInstanceCatChips() {
    if (!instanceCatChipsEl) return;
    var counts = {};
    instanceList.forEach(function (i) {
      (i.categories || []).forEach(function (c) { counts[c] = (counts[c] || 0) + 1; });
    });
    var slugs = Object.keys(counts).sort(function (a, b) {
      return counts[b] - counts[a] || catLabel(a).localeCompare(catLabel(b));
    });
    var smallCount = instanceList.filter(function (i) { return (i.users || 0) < INSTANCE_SMALL_USERS; }).length;
    if (smallCount) { counts.__small = smallCount; slugs.push('__small'); }   // vždy na konci

    if (instanceRegionGroupEl) instanceRegionGroupEl.hidden = (slugs.length === 0);
    instanceCatChipsEl.innerHTML = '';
    slugs.forEach(function (slug) {
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'filter-chip' + (instanceCats.has(slug) ? ' active' : '');
      b.setAttribute('data-cat', slug);
      b.textContent = catLabel(slug) + ' ' + counts[slug];
      b.addEventListener('click', function () {
        if (instanceCats.has(slug)) instanceCats.delete(slug); else instanceCats.add(slug);
        b.classList.toggle('active');
        renderInstances();
        writeHash();
      });
      instanceCatChipsEl.appendChild(b);
    });
  }

  function renderInstances() {
    if (!instanceResultsEl) return;
    if (instanceState !== 'loaded') {
      if (instanceState === 'error' && instanceMetaEl) instanceMetaEl.textContent = t('instance_unavail');
      return;
    }
    instanceResultsEl.innerHTML = '';

    var list = filteredInstances();
    var metaNote = '';
    if (instanceTab === 'ratio' || instanceTab === 'volume') {
      // Žebříček podle aktivity — jen HLAVNÍ instance (CZ/SK, nad práh „malé"), top N.
      var metric = instanceTab === 'ratio' ? instRatio : instVolume;
      list = list.filter(function (i) { return i.czsk && (i.users || 0) >= INSTANCE_SMALL_USERS; })
                 .slice().sort(function (a, b) { return metric(b) - metric(a); })
                 .slice(0, INSTANCE_RANK_TOP);
      metaNote = ' · ' + t(instanceTab === 'ratio' ? 'irank_ratio_note' : 'irank_volume_note');
    } else {
      var key = INSTANCE_SORT_KEY[instanceSort] || 'users';
      list = list.slice().sort(function (a, b) { return (b[key] || 0) - (a[key] || 0); });
      var limit = instanceTab === '10' ? 10 : instanceTab === '50' ? 50 : Infinity;
      list = list.slice(0, limit);
    }
    if (instanceMetaEl) instanceMetaEl.textContent = list.length + ' ' + t('instance_count') + metaNote;

    if (!list.length) {
      var z = document.createElement('p');
      z.className = 's-empty'; z.textContent = t('search_zero');
      instanceResultsEl.appendChild(z);
      return;
    }
    // 3 sekce: hlavní CZ/SK → malé/osobní → další (zahraniční s CZ/SK účty).
    // Dělení malých je čistě dle velikosti, takže komunitní/regionální instance
    // (boskovice, kompost) zůstanou v hlavní sekci.
    var small = list.filter(function (i) { return (i.users || 0) < INSTANCE_SMALL_USERS; });
    var big = list.filter(function (i) { return (i.users || 0) >= INSTANCE_SMALL_USERS; });
    appendInstanceSection(t('instance_sec_czsk'), big.filter(function (i) { return i.czsk; }));
    appendInstanceSection(t('instance_sec_small'), small);
    appendInstanceSection(t('instance_sec_other'), big.filter(function (i) { return !i.czsk; }));
  }

  function updateInstanceTabsUI() {
    if (!instanceTabsEl) return;
    instanceTabsEl.querySelectorAll('.tab[data-itab]').forEach(function (tab) {
      tab.classList.toggle('is-active', tab.getAttribute('data-itab') === instanceTab);
    });
  }

  function bindInstanceControls() {
    if (instanceTabsEl) {
      instanceTabsEl.querySelectorAll('.tab[data-itab]').forEach(function (tab) {
        tab.addEventListener('click', function () {
          instanceTab = tab.getAttribute('data-itab');
          updateInstanceTabsUI();
          renderInstances();
          writeHash();
        });
      });
    }
    if (instanceSearchEl) {
      instanceSearchEl.addEventListener('input', function () {
        instanceQuery = instanceSearchEl.value.trim();
        renderInstances();
      });
    }
    if (instanceSortEl) {
      instanceSortEl.addEventListener('change', function () {
        instanceSort = instanceSortEl.value;
        renderInstances();
      });
    }
  }

  function appendInstanceSection(label, list) {
    if (!list.length) return;
    var h = document.createElement('h2');
    h.className = 's-sec';
    h.textContent = label + ' ';
    var s = document.createElement('span'); s.textContent = list.length; h.appendChild(s);
    instanceResultsEl.appendChild(h);
    var grid = document.createElement('div');
    grid.className = 'cards-grid';
    list.forEach(function (i) { grid.appendChild(buildInstanceCard(i)); });
    instanceResultsEl.appendChild(grid);
  }

  // ========================================================
  // Pohled: Odkazy (kurátorovaný rozcestník z links.js)
  // ========================================================
  var LINK_TYPE_ORDER = ['explainer', 'navod', 'provozovatel', 'kontext'];

  function linkFreshness(f) {
    if (!f || f === 'undated') return t('lfresh_undated');
    if (f === 'current') return t('lfresh_current');
    return f;   // např. "2022-11"
  }

  function buildLinkCard(l) {
    var card = document.createElement('article');
    card.className = 'link-card';

    var a = document.createElement('a');
    a.className = 'link-title';
    a.href = l.url; a.target = '_blank'; a.rel = 'noopener noreferrer';
    a.textContent = l.title;
    card.appendChild(a);

    var meta = document.createElement('div');
    meta.className = 'link-meta';
    var lang = document.createElement('span');
    lang.className = 'link-lang link-lang-' + l.lang;
    lang.textContent = (l.lang || '').toUpperCase();
    meta.appendChild(lang);
    var src = document.createElement('span'); src.className = 'link-src'; src.textContent = l.source || '';
    meta.appendChild(src);
    var fr = document.createElement('span'); fr.className = 'link-fresh'; fr.textContent = linkFreshness(l.freshness);
    meta.appendChild(fr);
    card.appendChild(meta);

    if (l.note) {
      var note = document.createElement('p'); note.className = 'link-note'; note.textContent = l.note;
      card.appendChild(note);
    }
    return card;
  }

  function renderLinks() {
    if (!linksResultsEl) return;
    var data = (window.SLONIK_LINKS || []).filter(function (l) {
      if (linkTypes.size && !linkTypes.has(l.type)) return false;
      if (linkLangs.size && !linkLangs.has(l.lang)) return false;
      return true;
    });
    if (linksMetaEl) linksMetaEl.textContent = data.length + ' ' + t('links_count');
    linksResultsEl.innerHTML = '';
    if (!data.length) {
      var z = document.createElement('p'); z.className = 's-empty'; z.textContent = t('links_zero');
      linksResultsEl.appendChild(z);
      return;
    }
    // Seskup podle typu (v pevném pořadí), uvnitř cs před en.
    LINK_TYPE_ORDER.forEach(function (type) {
      var list = data.filter(function (l) { return l.type === type; })
                     .sort(function (a, b) { return (a.lang === b.lang) ? 0 : (a.lang === 'cs' ? -1 : 1); });
      if (!list.length) return;
      var h = document.createElement('h2'); h.className = 's-sec';
      h.textContent = t('ltype_' + type) + ' ';
      var s = document.createElement('span'); s.textContent = list.length; h.appendChild(s);
      linksResultsEl.appendChild(h);
      var grid = document.createElement('div'); grid.className = 'cards-grid';
      list.forEach(function (l) { grid.appendChild(buildLinkCard(l)); });
      linksResultsEl.appendChild(grid);
    });
  }

  function bindLinksControls() {
    document.querySelectorAll('#links-type-group button[data-ltype]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var v = btn.getAttribute('data-ltype');
        if (linkTypes.has(v)) linkTypes.delete(v); else linkTypes.add(v);
        btn.classList.toggle('active');
        renderLinks(); writeHash();
      });
    });
    document.querySelectorAll('#links-lang-group button[data-llang]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var v = btn.getAttribute('data-llang');
        if (linkLangs.has(v)) linkLangs.delete(v); else linkLangs.add(v);
        btn.classList.toggle('active');
        renderLinks(); writeHash();
      });
    });
  }

  function updatePostsTabsUI() {
    if (!postsTabsEl) return;
    postsTabsEl.querySelectorAll('.tab[data-ptab]').forEach(function (tab) {
      tab.classList.toggle('is-active', tab.getAttribute('data-ptab') === postsTab);
    });
  }

  function updateViewSwitchUI() {
    document.querySelectorAll('[data-view]').forEach(function (btn) {
      btn.classList.toggle('is-active', btn.getAttribute('data-view') === view);
    });
  }

  // Nadpis filtru Oblast: u Postů/Vyhledávání je téma dle ÚČTU (ne postu) → upřesnit.
  function updateFamilyHeading() {
    var h = document.querySelector('.filter-group[data-filter="family"] h2');
    if (!h) return;
    h.textContent = (view === 'posty' || view === 'search') ? t('head_topic_byaccount') : t('head_topic');
  }

  function bindPostsControls() {
    if (postsSortEl) {
      postsSortEl.addEventListener('change', function () {
        postsSort = postsSortEl.value;
        renderPosts();
        writeHash();
      });
    }
    if (postsTabsEl) {
      postsTabsEl.querySelectorAll('.tab[data-ptab]').forEach(function (tab) {
        tab.addEventListener('click', function () {
          postsTab = tab.getAttribute('data-ptab');
          updatePostsTabsUI();
          renderPosts();
          writeHash();
        });
      });
    }
  }

  // Lazy fetch posts.json — jen jednou, při prvním vstupu do pohledu Posty.
  function ensurePostsLoaded() {
    if (postsLoadState === 'loaded' || postsLoadState === 'loading') return;
    postsLoadState = 'loading';
    postsLoadingEl.hidden = false;
    postsUnavailableEl.hidden = true;
    postsEmptyEl.hidden = true;
    fetch('posts.json', { cache: 'no-cache' })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (data) {
        postsData = data;
        postsLoadState = 'loaded';
        postsLoadingEl.hidden = true;
        renderPosts();
      })
      .catch(function (err) {
        postsLoadState = 'error';
        postsLoadingEl.hidden = true;
        // posts.json vzniká vždy v pondělí v 03:00 — chybějící soubor = fallback hláška.
        if (view === 'posty') {
          postsGridEl.innerHTML = '';
          postsUnavailableEl.hidden = false;
        }
        console.warn('posts.json load failed:', err);
      });
  }

  // Sekce posts.json → klíč podle aktuálního řazení (žebříčky).
  var POSTS_SECTION = {
    engagement: 'top_by_engagement', reblogs: 'top_by_reblogs',
    favourites: 'top_by_favourites', date: 'top_by_date', date_asc: 'top_by_date'
  };

  function isRiserTab() {
    return postsTab === 'risers_ratio' || postsTab === 'risers_abs';
  }

  // Aktivní režim Skokanů podle pohledu (Posty i Vyhledávání sdílí buildPostCard).
  function activeRiserMode() {
    var tab = (view === 'search') ? searchTab : (view === 'posty') ? postsTab : null;
    return tab === 'risers_ratio' ? 'ratio' : tab === 'risers_abs' ? 'abs' : null;
  }

  // Vrátí výchozí pole postů podle aktuálního řezu/řazení (před filtry).
  function postsBaseList() {
    if (isRiserTab()) {
      var key = (postsTab === 'risers_ratio') ? 'risers_ratio' : 'risers_absolute';
      var arr = postsData[key] || postsData.risers || []; // fallback na starý klíč
      return arr.slice();
    }
    var section = POSTS_SECTION[postsSort] || 'top_by_engagement';
    var arr2 = (postsData[section] || []).slice();
    if (postsSort === 'date_asc') arr2.reverse(); // top_by_date je sestupně → otoč
    var limit = (postsTab === '10') ? 10 : (postsTab === '50') ? 50 : Infinity;
    return arr2.slice(0, limit);
  }

  function renderPosts() {
    if (view !== 'posty') return;
    if (postsLoadState === 'loading') { postsLoadingEl.hidden = false; return; }
    if (postsLoadState !== 'loaded' || !postsData) {
      if (postsLoadState === 'error') postsUnavailableEl.hidden = false;
      return;
    }
    postsLoadingEl.hidden = true;
    postsUnavailableEl.hidden = true;
    // V režimu Skokani je řazení dané metrikou → schovej výběr řazení.
    if (postsSortWrapEl) postsSortWrapEl.hidden = isRiserTab();

    var base = postsBaseList();

    // `base` = sekce + Top N. Hashtag chips počítáme z postů, které projdou
    // rodinou + fulltextem (ale BEZ hashtag filtru), ať nabídka zůstane stabilní.
    var beforeHashtag = base.filter(function (p) { return postMatchesFilters(p, true); });
    renderPostHashtagUI(beforeHashtag);

    // Finální seznam = navíc hashtag filtr.
    var list = beforeHashtag.filter(matchesPostHashtag);

    postsMetaEl.textContent = postsMetaText();

    postsGridEl.innerHTML = '';
    if (list.length === 0) {
      postsEmptyEl.hidden = false;
      return;
    }
    postsEmptyEl.hidden = true;
    var frag = document.createDocumentFragment();
    list.forEach(function (p) { frag.appendChild(buildPostCard(p)); });
    postsGridEl.appendChild(frag);
  }

  // skipHashtag=true → vynechá hashtag filtr (pro výpočet nabídky chips).
  function postMatchesFilters(p, skipHashtag) {
    if (filters.family.size && !filters.family.has(p.account_family)) return false;
    if (searchQuery) {
      var hay = ((p.content_plain || '') + ' ' + (p.account_display_name || '') + ' ' +
                 (p.account_username || '')).toLowerCase();
      if (hay.indexOf(searchQuery) === -1) return false;
    }
    if (!skipHashtag && !matchesPostHashtag(p)) return false;
    return true;
  }

  // AND přes vybrané hashtagy (post musí mít všechny zvolené).
  function matchesPostHashtag(p) {
    if (!postHashtags.size) return true;
    var hs = p.hashtags || [];
    var ok = true;
    postHashtags.forEach(function (h) { if (hs.indexOf(h) === -1) ok = false; });
    return ok;
  }

  var HASHTAG_CHIP_MAX = 30;  // kolik nejčastějších hashtagů nabídnout

  // Vykreslí vybrané hashtagy (nahoře) + nabídku chips (četnost z `posts`).
  function renderPostHashtagUI(posts) {
    if (!postHashtagChipsEl) return;
    var counts = {};
    posts.forEach(function (p) {
      (p.hashtags || []).forEach(function (h) { counts[h] = (counts[h] || 0) + 1; });
    });

    // Vybrané hashtagy (i ty s 0 výskyty v aktuální nabídce zůstanou zrušitelné).
    postHashtagSelectedEl.innerHTML = '';
    postHashtags.forEach(function (h) {
      var chip = document.createElement('button');
      chip.className = 'tag-chip tag-chip-selected';
      chip.appendChild(document.createTextNode('#' + h + ' '));
      var x = document.createElement('span');
      x.className = 'tag-x';
      x.textContent = '×';
      chip.appendChild(x);
      chip.setAttribute('aria-label', 'Odebrat hashtag ' + h);
      chip.addEventListener('click', function () { togglePostHashtag(h); });
      postHashtagSelectedEl.appendChild(chip);
    });

    // Nabídka — nejčastější hashtagy, které ještě nejsou vybrané.
    postHashtagChipsEl.innerHTML = '';
    var entries = Object.keys(counts)
      .filter(function (h) { return !postHashtags.has(h); })
      .sort(function (a, b) { return counts[b] - counts[a] || a.localeCompare(b); })
      .slice(0, HASHTAG_CHIP_MAX);

    if (entries.length === 0 && postHashtags.size === 0) {
      var empty = document.createElement('p');
      empty.className = 'hashtags-empty';
      empty.textContent = t('hashtags_empty');
      postHashtagChipsEl.appendChild(empty);
      return;
    }
    entries.forEach(function (h) {
      var chip = document.createElement('button');
      chip.className = 'tag-chip';
      chip.appendChild(document.createTextNode('#' + h + ' '));
      var c = document.createElement('span');
      c.className = 'tag-count';
      c.textContent = counts[h];
      chip.appendChild(c);
      chip.addEventListener('click', function () { togglePostHashtag(h); });
      postHashtagChipsEl.appendChild(chip);
    });
  }

  function togglePostHashtag(h) {
    if (postHashtags.has(h)) postHashtags.delete(h); else postHashtags.add(h);
    if (view === 'search') renderSearch(); else renderPosts();
    writeHash();
  }

  function postsMetaText() {
    if (!postsData) return '';
    var wk = formatWeek(postsData.week);
    var cnt = postsData.total_posts != null
      ? (postsData.total_posts + ' ' + t('posts_count')) : '';
    return [wk, cnt].filter(Boolean).join(' · ');
  }

  // "2026-W22" → cs "22. týden 2026", en "week 22, 2026"
  function formatWeek(week) {
    if (!week) return '';
    var m = String(week).match(/^(\d{4})-W(\d{2})$/);
    if (!m) return week;
    var year = m[1], num = parseInt(m[2], 10);
    return lang === 'en' ? ('week ' + num + ', ' + year)
                         : (num + '. ' + t('posts_week') + ' ' + year);
  }

  // ---------- Karta postu ----------
  var POST_TEXT_LIMIT = 280;

  function buildPostCard(p) {
    var card = document.createElement('article');
    card.className = 'post-card';

    // --- Hlavička: avatar + jméno/handle (prolink na profil) + rodina ---
    var head = document.createElement('div');
    head.className = 'post-head';
    var profileUrl = 'https://' + p.account_instance + '/@' + p.account_username;

    var avatarLink = document.createElement('a');
    avatarLink.className = 'post-avatar-link';
    avatarLink.href = profileUrl;
    avatarLink.target = '_blank';
    avatarLink.rel = 'noopener';
    avatarLink.title = t('profile_title');
    avatarLink.appendChild(buildAvatar({ avatar: p.account_avatar }, 'card-avatar'));
    head.appendChild(avatarLink);

    var hbody = document.createElement('div');
    hbody.className = 'post-head-body';
    var author = document.createElement('a');
    author.className = 'post-author';
    author.href = profileUrl;
    author.target = '_blank';
    author.rel = 'noopener';
    author.title = t('profile_title');
    author.textContent = cleanName(p.account_display_name) || p.account_username;
    var handle = document.createElement('div');
    handle.className = 'post-handle';
    handle.textContent = '@' + p.account_username + '@' + p.account_instance;
    hbody.appendChild(author);
    hbody.appendChild(handle);
    head.appendChild(hbody);
    // Oblast (rodina) se na kartě postu nezobrazuje — mátlo to (zůstává jen ve filtru).
    card.appendChild(head);

    // --- Text postu (klikatelné odkazy z content_html; „zobrazit více") ---
    var plain = (p.content_plain || '').trim();
    if (plain === '') {
      var empty = document.createElement('p');
      empty.className = 'post-text is-empty';
      empty.textContent = t('post_media_only');
      card.appendChild(empty);
    } else {
      var text = document.createElement('p');
      text.className = 'post-text';
      // Klikatelný obsah ze sanitizovaného HTML (fallback na plain text).
      if (p.content_html) {
        text.appendChild(sanitizePostHtml(p.content_html));
      } else {
        text.textContent = plain;
      }
      // Dlouhý post → zkrátit přes CSS clamp + tlačítko „zobrazit více".
      if (plain.length > POST_TEXT_LIMIT) {
        text.classList.add('is-clamped');
        var more = document.createElement('button');
        more.type = 'button';
        more.className = 'post-more';
        more.textContent = t('post_more');
        more.addEventListener('click', function () {
          text.classList.remove('is-clamped');
          more.remove();
        });
        card.appendChild(text);
        card.appendChild(more);
      } else {
        card.appendChild(text);
      }
    }

    // --- Příloha (jen badge, ne náhled) ---
    if (p.has_media) {
      var media = document.createElement('span');
      media.className = 'post-media-badge';
      media.textContent = '📷 ' + t('post_media');
      card.appendChild(media);
    }

    // Hashtagy postu jsou klikatelné přímo v textu (sanitizePostHtml) — žádná
    // duplicitní řada chips pod textem. Tagy účtu se na kartě postu nezobrazují
    // (mátlo to uživatele) — zůstávají jen jako filtr v menu.

    // --- Patička: stats + odkaz ---
    var foot = document.createElement('div');
    foot.className = 'post-foot';
    foot.appendChild(postStat('🔁', formatNumber(p.reblogs_count || 0)));
    foot.appendChild(postStat('⭐', formatNumber(p.favourites_count || 0)));
    foot.appendChild(postStat('📅', formatPostDate(p.created_at)));
    // Skokan badge — podle aktivní metriky: poměrem (×N) nebo dosahem (+N).
    var riserMode = activeRiserMode();
    if (riserMode === 'ratio' && p.riser_ratio != null) {
      var riserR = document.createElement('span');
      riserR.className = 'post-riser-badge';
      riserR.textContent = '🚀 ' + t('post_riser') + ' ×' + p.riser_ratio.toFixed(1);
      foot.appendChild(riserR);
    } else if (riserMode === 'abs' && p.riser_score != null) {
      var riserA = document.createElement('span');
      riserA.className = 'post-riser-badge';
      riserA.textContent = '🚀 ' + t('post_riser') + ' +' + Math.round(p.riser_score);
      foot.appendChild(riserA);
    }
    if (p.url) {
      var open = document.createElement('a');
      open.className = 'post-open';
      open.href = p.url;
      open.target = '_blank';
      open.rel = 'noopener';
      open.textContent = '↗ ' + t('post_open');
      foot.appendChild(open);
    }
    card.appendChild(foot);

    return card;
  }

  function postStat(icon, value) {
    var s = document.createElement('span');
    s.className = 'post-stat';
    var v = document.createElement('strong');
    v.textContent = value;
    s.appendChild(document.createTextNode(icon + ' '));
    s.appendChild(v);
    return s;
  }

  function formatPostDate(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    if (lang === 'en') {
      return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
    }
    return d.getDate() + '. ' + (d.getMonth() + 1) + '. ' + d.getFullYear();
  }

  // ---------- Konstanty chování ----------
  var RECENT_DAYS = 90;     // okno pro řez "Nedávno přidané"
  var ACTIVE_DAYS = 90;     // účet bez příspěvku déle (≈3 měsíce) se nezobrazuje
  var HOVER_DELAY = 400;    // ms než se ukáže hover preview
  var HOVER_GRACE = 200;    // ms tolerance po odjezdu myši
  var TAG_CHIP_COUNT = 10;  // počet nejčastějších tagů jako chips
  var SUGGEST_MAX = 8;      // max položek v autocomplete

  var HOVER_CAPABLE = window.matchMedia &&
    window.matchMedia('(hover: hover) and (pointer: fine)').matches;

  // Žebříčky: metrika řezu → pole záznamu (popisná fráze viz t('top_phrase_*')).
  var TOP_FIELD = {
    followers: 'followers', active: 'posts_week',
    gain_followers: 'followers_delta', gain_activity: 'activity_delta'
  };

  // ---------- Stav ----------
  var records = [];           // aktivní účty (Účty tab)
  var catalogById = {};       // CELÝ katalog (i neaktivní) — pro vyhledávání
  var filters = { family: new Set(), type: new Set(), language: new Set(), tag: new Set() };
  var searchQuery = '';
  var sortKey = 'name';
  var slice = { kind: 'all' };   // all | platform:<p> | top:<metric>:<n> | recent

  // ---------- Stav pohledu na posty ----------
  var view = 'search';           // výchozí pohled při načtení (bez #hash)
  var postsData = null;          // načtený posts.json (null = ještě nenačteno)
  var postsLoadState = 'idle';   // idle | loading | loaded | error
  var postsSort = 'engagement';  // engagement | reblogs | favourites | date | date_asc
  var postsTab = 'all';          // 'all' | '10' | '50' | 'risers_ratio' | 'risers_abs'
  var aboutSection = 'about';    // 'about' | 'accounts' | 'posts'
  var postHashtags = new Set();  // vybrané hashtagy (AND filtr v posts view)
  // ---------- Stav vyhledávání ----------
  var searchState = 'idle';      // idle | loading | loaded | error
  var searchPromise = null;
  var searchPosts = [];          // search.json posts
  var searchUsers = [];          // users.json users
  var searchTab = 'all';         // 'all' | '10' | '50' | 'risers_ratio' | 'risers_abs'
  var searchSort = 'relevance';  // relevance | date | engagement | reblogs | favourites
  // ---------- Stav instancí ----------
  var instanceState = 'idle';
  var instancePromise = null;
  var instanceList = [];         // instances.json
  var instanceTab = 'all';       // 'all' | '10' | '50' | 'ratio' | 'volume'
  var instanceQuery = '';        // fulltext nad doménou/názvem/popisem
  var instanceSort = 'users';    // users | active | catalog | posts
  var instanceCats = new Set();  // zvolené oblasti (kategorie joinmastodon)
  // ---------- Stav Odkazů ----------
  var linkTypes = new Set();     // filtr typu (explainer/navod/provozovatel/kontext)
  var linkLangs = new Set();     // filtr jazyka (cs/en)

  // ---------- DOM ----------
  var cardsEl, emptyEl, loadingEl, searchEl, resetEl, emptyResetEl,
      visibleCountEl, totalCountEl, sortEl, sliceNoteEl, tabsEl,
      tagInputEl, tagSuggestEl, tagSelectedEl, tagChipsEl,
      sidebarEl, sidebarToggleEl, modalEl, hoverEl, institutionBtnEl,
      accountsViewEl, postsViewEl, aboutViewEl, postsGridEl, postsLoadingEl, postsEmptyEl,
      postsUnavailableEl, postsSortEl, postsSortWrapEl, postsTabsEl, postsMetaEl,
      postHashtagsGroupEl, postHashtagChipsEl, postHashtagSelectedEl, aboutNavEl,
      cardsSentinelEl, searchViewEl, searchQEl, searchMetaEl, searchResultsEl, searchNavEl,
      accountsNavEl, postsNavEl,
      searchTabsEl, searchSortEl, searchSortWrapEl,
      instanceViewEl, instanceNavEl, instanceMetaEl, instanceResultsEl,
      instanceTabsEl, instanceSearchEl, instanceSearchWrapEl, instanceSortEl,
      instanceSortWrapEl, instanceRegionGroupEl, instanceCatChipsEl,
      linksViewEl, linksNavEl, linksMetaEl, linksResultsEl, linksTabsEl, slicesHeadingEl;

  // ---------- Inkrementální vykreslování karet (infinite scroll) ----------
  var CARDS_BATCH = 60;       // kolik karet vykreslit najednou
  var pageRecords = [];       // aktuální vyfiltrovaný seznam
  var pageRendered = 0;       // kolik z něj už je v DOM
  var cardsObserver = null;   // IntersectionObserver nad sentinelem

  var suppressHash = false;   // brání smyčce při programovém zápisu do hash
  var hoverTimer = null, hoverHideTimer = null;
  var pendingAccountId = null;  // z #account=<id> (per-účet sdílecí stub) → otevřít modal
  var pendingSearchQ = '';      // z #sq=<dotaz> → předvyplnit vyhledávací pole

  document.addEventListener('DOMContentLoaded', function () {
    cardsEl        = document.getElementById('cards');
    cardsSentinelEl = document.getElementById('cards-sentinel');
    emptyEl        = document.getElementById('empty-state');
    loadingEl      = document.getElementById('loading-state');
    searchEl       = document.getElementById('search');
    resetEl        = document.getElementById('reset-filters');
    emptyResetEl   = document.getElementById('empty-reset');
    visibleCountEl = document.getElementById('visible-count');
    totalCountEl   = document.getElementById('total-count');
    sortEl         = document.getElementById('sort');
    sliceNoteEl    = document.getElementById('slice-note');
    tabsEl         = document.getElementById('tabs');
    tagInputEl     = document.getElementById('tag-input');
    tagSuggestEl   = document.getElementById('tag-suggestions');
    tagSelectedEl  = document.getElementById('tag-selected');
    tagChipsEl     = document.getElementById('tag-chips');
    sidebarEl      = document.getElementById('sidebar');
    sidebarToggleEl = document.getElementById('sidebar-toggle');
    modalEl        = document.getElementById('detail-modal');
    institutionBtnEl = document.querySelector('.filter-group[data-filter="type"] button[data-value="institution"]');
    hoverEl        = buildHoverEl();

    accountsViewEl     = document.querySelector('.catalog:not(.posts-view)');
    postsViewEl        = document.getElementById('posts-view');
    aboutViewEl        = document.getElementById('about-view');
    aboutNavEl         = document.getElementById('about-nav');
    searchViewEl       = document.getElementById('search-view');
    searchNavEl        = document.getElementById('search-nav');
    accountsNavEl      = document.getElementById('accounts-nav');
    postsNavEl         = document.getElementById('posts-nav');
    searchTabsEl       = document.getElementById('search-tabs');
    searchSortEl       = document.getElementById('search-sort-select');
    searchSortWrapEl   = document.getElementById('search-sort-wrap');
    searchQEl          = document.getElementById('search-q');
    searchMetaEl       = document.getElementById('search-meta');
    searchResultsEl    = document.getElementById('search-results');
    instanceViewEl     = document.getElementById('instance-view');
    instanceNavEl      = document.getElementById('instance-nav');
    instanceMetaEl     = document.getElementById('instance-meta');
    instanceResultsEl  = document.getElementById('instance-results');
    instanceTabsEl     = document.getElementById('instance-tabs');
    instanceSearchEl   = document.getElementById('instance-search');
    instanceSearchWrapEl = document.getElementById('instance-search-wrap');
    instanceSortEl     = document.getElementById('instance-sort-select');
    instanceSortWrapEl = document.getElementById('instance-sort-wrap');
    instanceRegionGroupEl = document.getElementById('instance-region-group');
    instanceCatChipsEl = document.getElementById('instance-cat-chips');
    linksViewEl        = document.getElementById('links-view');
    linksNavEl         = document.getElementById('links-nav');
    linksMetaEl        = document.getElementById('links-meta');
    linksResultsEl     = document.getElementById('links-results');
    linksTabsEl        = document.getElementById('links-tabs');
    slicesHeadingEl    = document.getElementById('slices-heading');
    postsGridEl        = document.getElementById('posts-grid');
    postsLoadingEl     = document.getElementById('posts-loading');
    postsEmptyEl       = document.getElementById('posts-empty');
    postsUnavailableEl = document.getElementById('posts-unavailable');
    postsSortEl        = document.getElementById('posts-sort-select');
    postsSortWrapEl    = document.getElementById('posts-sort-wrap');
    postsTabsEl        = document.getElementById('posts-tabs');
    postsMetaEl        = document.getElementById('posts-meta');
    postHashtagsGroupEl    = document.getElementById('post-hashtags-group');
    postHashtagChipsEl     = document.getElementById('post-hashtag-chips');
    postHashtagSelectedEl  = document.getElementById('post-hashtag-selected');

    initLang();
    applyI18n();
    bindLangSwitch();
    bindViewSwitch();
    bindPostsControls();
    bindInstanceControls();
    bindLinksControls();
    bindAboutNav();
    bindSearchView();
    bindFilterButtons();
    bindSearch();
    bindSort();
    bindReset();
    bindTabs();
    bindTagFilter();
    bindSidebarToggle();
    bindModalClose();
    bindHeroHome();
    setupCardsPaging();
    placeSliceTabs();
    window.matchMedia('(max-width: 760px)').addEventListener('change', placeSliceTabs);
    renderUpdatedRelative();
    renderSearchIndexed();

    parseHash();
    applyStateToControls();
    window.addEventListener('hashchange', onHashChange);

    fetch('data.json', { cache: 'no-cache' })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var raw = Array.isArray(data) ? data : [];
        // Mastodon custom-emoji shortcody (např. trailing :bot:) se renderují jako
        // holý text — odstraníme je z jména hned, ať je čisté i pro hledání/řazení.
        raw.forEach(function (r) { r.display_name = cleanName(r.display_name); });
        // Vyhledávání ukazuje VŠECHNY účty (i neaktivní) → mapa celého katalogu.
        catalogById = {};
        raw.forEach(function (r) { catalogById[r.id] = r; });
        // Účty (Účty tab) zobrazují jen aktivní (poslední příspěvek do ACTIVE_DAYS).
        records = raw.filter(isActive);
        loadingEl.hidden = true;
        if (totalCountEl) totalCountEl.textContent = records.length;
        render();
        maybeOpenPendingAccount();
      })
      .catch(function (err) {
        loadingEl.hidden = true;
        cardsEl.innerHTML = '<p class="load-error">' + t('load_error') + '</p>';
        console.error('Catalog load failed:', err);
      });
  });

  // ========================================================
  // Bindings
  // ========================================================
  function bindFilterButtons() {
    document.querySelectorAll('.filter-group[data-filter="family"] button[data-value],' +
      '.filter-group[data-filter="type"] button[data-value],' +
      '.filter-group[data-filter="language"] button[data-value]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var section = btn.closest('.filter-group').getAttribute('data-filter');
        toggleSetValue(filters[section], btn.getAttribute('data-value'));
        btn.classList.toggle('active');
        render();
      });
    });
  }

  function bindSearch() {
    searchEl.addEventListener('input', function () {
      searchQuery = searchEl.value.trim().toLowerCase();
      render();
    });
  }

  function bindSort() {
    sortEl.addEventListener('change', function () {
      sortKey = sortEl.value;
      render();
    });
  }

  function bindReset() {
    resetEl.addEventListener('click', resetAll);
    emptyResetEl.addEventListener('click', resetAll);
  }

  function bindTabs() {
    tabsEl.querySelectorAll('.tab').forEach(function (tab) {
      tab.addEventListener('click', function () {
        slice = parseSlice(tab.getAttribute('data-slice'));
        render();
      });
    });
  }

  // Popisek tlačítka menu podle stavu (Zobrazit/Skrýt) + aktuálního jazyka.
  function updateSidebarToggleLabel() {
    var el = document.getElementById('sidebar-toggle-label');
    if (!el || !sidebarEl) return;
    el.textContent = t(sidebarEl.classList.contains('open') ? 'menu_hide' : 'menu_show');
  }

  // Řezy lišty (Vše/Top/Skokani… per pohled) jsou v DOM mezi navbarem a obsahem.
  // Na mobilu je přesuneme DO draweru za „Pohledy" (POHLEDY → řezy → filtry);
  // na desktopu zpět pod navbar (horizontální lišta). Volá se i při změně šířky.
  function placeSliceTabs() {
    var slices = [tabsEl, postsTabsEl, searchTabsEl, instanceTabsEl, linksTabsEl].filter(Boolean);
    if (!slices.length) return;
    var mobile = window.matchMedia('(max-width: 760px)').matches;
    if (mobile) {
      var head = document.getElementById('slices-heading');
      if (!head) return;
      slices.forEach(function (el) { head.appendChild(el); });  // do sekce „Rychlé filtry", v pořadí
    } else {
      var main = document.querySelector('main.layout');
      if (!main || !main.parentNode) return;
      slices.forEach(function (el) { main.parentNode.insertBefore(el, main); });  // zpět pod navbar
    }
  }

  function bindSidebarToggle() {
    sidebarToggleEl.addEventListener('click', function () {
      var open = sidebarEl.classList.toggle('open');
      sidebarToggleEl.setAttribute('aria-expanded', open ? 'true' : 'false');
      updateSidebarToggleLabel();
    });
  }

  // Klik na hlavičkový obrázek = návrat na "Vše" (reset všech filtrů a řezů).
  function bindHeroHome() {
    var hero = document.getElementById('hero-home');
    if (hero) hero.addEventListener('click', resetAll);
  }

  // Odstraní Mastodon custom-emoji shortcody (`:bot:`, `:verified:` …) z jména.
  function cleanName(name) {
    return String(name == null ? '' : name)
      .replace(/:[a-zA-Z0-9_]+:/g, '')
      .replace(/\s{2,}/g, ' ')
      .trim();
  }

  // ========================================================
  // Tag filtr (autocomplete + dynamické chips)
  // ========================================================
  function bindTagFilter() {
    tagInputEl.addEventListener('input', function () { renderTagSuggestions(); });
    tagInputEl.addEventListener('focus', function () { renderTagSuggestions(); });
    tagInputEl.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        var first = tagSuggestEl.querySelector('li');
        if (first) addTag(first.getAttribute('data-tag'));
      } else if (e.key === 'Escape') {
        hideTagSuggestions();
      }
    });
    document.addEventListener('click', function (e) {
      if (!e.target.closest('.tag-autocomplete')) hideTagSuggestions();
    });
  }

  function addTag(tag) {
    if (!tag) return;
    filters.tag.add(tag);
    tagInputEl.value = '';
    hideTagSuggestions();
    render();
  }

  function removeTag(tag) {
    filters.tag.delete(tag);
    render();
  }

  function hideTagSuggestions() {
    tagSuggestEl.hidden = true;
    tagSuggestEl.innerHTML = '';
    tagInputEl.setAttribute('aria-expanded', 'false');
  }

  // Tagy dostupné v aktuálním výběru (slice + ostatní filtry kromě tagu), s četností.
  function availableTagCounts() {
    var counts = Object.create(null);
    sliceBase().filter(matchesExceptTag).forEach(function (rec) {
      (rec.categories || []).forEach(function (t) {
        counts[t] = (counts[t] || 0) + 1;
      });
    });
    return counts;
  }

  function renderTagSuggestions() {
    var q = tagInputEl.value.trim().toLowerCase();
    var counts = availableTagCounts();
    var list = Object.keys(counts)
      .filter(function (t) { return !filters.tag.has(t) && t.indexOf(q) !== -1; })
      .sort(function (a, b) { return counts[b] - counts[a] || a.localeCompare(b); })
      .slice(0, SUGGEST_MAX);

    tagSuggestEl.innerHTML = '';
    if (list.length === 0) { hideTagSuggestions(); return; }
    list.forEach(function (t) {
      var li = document.createElement('li');
      li.setAttribute('role', 'option');
      li.setAttribute('data-tag', t);
      li.innerHTML = '';
      var name = document.createElement('span');
      name.textContent = t;
      var c = document.createElement('span');
      c.className = 'tag-count';
      c.textContent = counts[t];
      li.appendChild(name);
      li.appendChild(c);
      li.addEventListener('click', function () { addTag(t); });
      tagSuggestEl.appendChild(li);
    });
    tagSuggestEl.hidden = false;
    tagInputEl.setAttribute('aria-expanded', 'true');
  }

  // Vybrané tagy (odstranitelné chips) + top-N návrhové chips.
  function renderTagUI() {
    tagSelectedEl.innerHTML = '';
    filters.tag.forEach(function (t) {
      var chip = document.createElement('button');
      chip.className = 'tag-chip tag-chip-selected';
      chip.innerHTML = '';
      chip.appendChild(document.createTextNode(t));
      var x = document.createElement('span');
      x.className = 'tag-x';
      x.setAttribute('aria-hidden', 'true');
      x.textContent = '×';
      chip.appendChild(x);
      chip.setAttribute('aria-label', 'Odebrat tag ' + t);
      chip.addEventListener('click', function () { removeTag(t); });
      tagSelectedEl.appendChild(chip);
    });

    var counts = availableTagCounts();
    var top = Object.keys(counts)
      .filter(function (t) { return !filters.tag.has(t); })
      .sort(function (a, b) { return counts[b] - counts[a] || a.localeCompare(b); })
      .slice(0, TAG_CHIP_COUNT);

    tagChipsEl.innerHTML = '';
    top.forEach(function (t) {
      var chip = document.createElement('button');
      chip.className = 'tag-chip';
      chip.appendChild(document.createTextNode(t));
      var c = document.createElement('span');
      c.className = 'tag-count';
      c.textContent = counts[t];
      chip.appendChild(c);
      chip.addEventListener('click', function () { addTag(t); });
      tagChipsEl.appendChild(chip);
    });
  }

  // ========================================================
  // Filtrování + řezy
  // ========================================================
  function toggleSetValue(set, value) {
    if (set.has(value)) set.delete(value); else set.add(value);
  }

  // Záznamy spadající do aktuálního řezu, bez sidebar filtrů (kromě Top N, které
  // řeší jen rodinu). Slouží jako základ pro počítání dostupných tagů.
  function sliceBase() {
    if (slice.kind === 'top') {
      return records.filter(function (r) {
        return filters.family.size === 0 || filters.family.has(r.family);
      });
    }
    return records.filter(inSlice);
  }

  function inSlice(rec) {
    if (slice.kind === 'platform') {
      return (rec.source_platforms || []).indexOf(slice.value) !== -1;
    }
    if (slice.kind === 'recent') {
      var d = daysSince(rec.created_at);
      return d !== null && d <= RECENT_DAYS;
    }
    return true; // all
  }

  function matchesExceptTag(rec) {
    if (filters.family.size && !filters.family.has(rec.family)) return false;
    if (filters.type.size && !filters.type.has(rec.type)) return false;
    if (filters.language.size && !filters.language.has(rec.language)) return false;
    if (searchQuery) {
      // Vyhledává jméno + handle + (skrytě) tagy — "f1" tak najde i účty,
      // které f1 nemají ve jméně, ale jsou tak otagované.
      var hay = (rec.display_name + ' ' + rec.id + ' ' +
                 (rec.categories || []).join(' ')).toLowerCase();
      if (hay.indexOf(searchQuery) === -1) return false;
    }
    return true;
  }

  function matchesTag(rec) {
    if (!filters.tag.size) return true;
    var cats = rec.categories || [];
    var ok = true;
    filters.tag.forEach(function (t) { if (cats.indexOf(t) === -1) ok = false; });
    return ok;
  }

  // Top N přepisuje ostatní filtry — kurátorský pohled, respektuje jen rodinu.
  function isTopSlice() { return slice.kind === 'top'; }

  function computeVisible() {
    if (isTopSlice()) {
      var field = TOP_FIELD[slice.metric] || 'followers';
      var isGain = slice.metric.indexOf('gain_') === 0;
      return records
        .filter(function (r) {
          if (filters.family.size && !filters.family.has(r.family)) return false;
          // Skokani: jen účty s kladným nárůstem a dostupnou předchozí hodnotou.
          if (isGain) return r[field] != null && r[field] > 0;
          return true;
        })
        .slice()
        .sort(function (a, b) { return (b[field] || 0) - (a[field] || 0); })
        .slice(0, slice.count);
    }
    var list = records.filter(function (r) {
      return inSlice(r) && matchesExceptTag(r) && matchesTag(r);
    });
    return sortList(list);
  }

  function sortList(list) {
    var copy = list.slice();
    switch (sortKey) {
      case 'followers':
        copy.sort(function (a, b) { return (b.followers || 0) - (a.followers || 0); });
        break;
      case 'posts':
        copy.sort(function (a, b) { return (b.posts_week || 0) - (a.posts_week || 0); });
        break;
      case 'added':
        copy.sort(function (a, b) {
          var da = a.created_at || '', db = b.created_at || '';
          if (da === db) return cmpName(a, b);
          if (!da) return 1; if (!db) return -1;       // bez data na konec
          return db < da ? -1 : 1;                      // novější (větší datum) první
        });
        break;
      default:
        copy.sort(cmpName);
    }
    return copy;
  }

  function cmpName(a, b) {
    return a.display_name.localeCompare(b.display_name, 'cs', { sensitivity: 'base' });
  }

  // ========================================================
  // Render
  // ========================================================
  // ---------- Inkrementální vykreslování (infinite scroll) ----------

  // Vykreslí další dávku karet (CARDS_BATCH) z pageRecords.
  function renderNextCardsBatch() {
    var end = Math.min(pageRendered + CARDS_BATCH, pageRecords.length);
    if (end <= pageRendered) return;
    var frag = document.createDocumentFragment();
    for (var i = pageRendered; i < end; i++) frag.appendChild(buildCard(pageRecords[i]));
    cardsEl.appendChild(frag);
    pageRendered = end;
  }

  // Dorenderovává dávky, dokud je sentinel ve výhledu (vyplní fold) nebo dokud
  // není vše hotovo. Volá se i z observeru při scrollování.
  function maybeRenderMoreCards() {
    if (!cardsSentinelEl || pageRendered >= pageRecords.length) return;
    var r = cardsSentinelEl.getBoundingClientRect();
    if (r.top <= (window.innerHeight || document.documentElement.clientHeight) + 400) {
      renderNextCardsBatch();
      requestAnimationFrame(maybeRenderMoreCards);
    }
  }

  // Observer nad sentinelem; když není k dispozici (starý prohlížeč), zvětší
  // dávku na „vše" → fallback na původní chování (vykreslí celý seznam).
  function setupCardsPaging() {
    if (!cardsSentinelEl) return;
    if (!('IntersectionObserver' in window)) { CARDS_BATCH = Infinity; return; }
    cardsObserver = new IntersectionObserver(function (entries) {
      if (entries[0].isIntersecting) maybeRenderMoreCards();
    }, { rootMargin: '400px 0px' });
    cardsObserver.observe(cardsSentinelEl);
  }

  function render() {
    syncTabsUI();
    updateSliceDimming();
    updateInstitutionFilterLabel();

    var visible = computeVisible();
    visibleCountEl.textContent = visible.length;

    renderTagUI();
    renderSliceNote();

    var anyFilter = filters.family.size || filters.type.size ||
      filters.language.size || filters.tag.size || searchQuery ||
      slice.kind !== 'all' || sortKey !== 'name';
    resetEl.hidden = !anyFilter;

    cardsEl.innerHTML = '';
    pageRecords = visible;
    pageRendered = 0;
    if (visible.length === 0) {
      emptyEl.hidden = false;
      if (cardsSentinelEl) cardsSentinelEl.hidden = true;
    } else {
      emptyEl.hidden = true;
      if (cardsSentinelEl) cardsSentinelEl.hidden = false;
      renderNextCardsBatch();   // první dávka
      maybeRenderMoreCards();   // dorenderuj, dokud sentinel není pod foldem
    }

    // Sdílené filtry (Oblast/Hashtagy) ovlivňují i Posty a Vyhledávání.
    if (view === 'posty') renderPosts();
    if (view === 'search') renderSearch();

    writeHash();
  }

  function renderSliceNote() {
    var note = '';
    if (slice.kind === 'platform') {
      note = t('slice_platform') + platformLabel(slice.value);
    } else if (slice.kind === 'recent') {
      note = t('slice_recent_pre') + RECENT_DAYS + t('slice_recent_post');
    } else if (slice.kind === 'top') {
      note = t('slice_top_pre') + slice.count + ' ' + t('top_phrase_' + slice.metric) + t('slice_top_post');
    }
    sliceNoteEl.textContent = note;
    sliceNoteEl.hidden = note === '';
  }

  // Top N ztlumí (disabled) vše kromě rodiny.
  function updateSliceDimming() {
    var dim = isTopSlice();
    document.querySelectorAll('.filter-group[data-filter="type"],' +
      '.filter-group[data-filter="language"], .filter-group[data-filter="tag"],' +
      '.filter-sort, .filter-search').forEach(function (el) {
      el.classList.toggle('is-dimmed', dim);
      el.querySelectorAll('input, button, select').forEach(function (c) { c.disabled = dim; });
    });
  }

  function syncTabsUI() {
    var current = sliceToString(slice);
    tabsEl.querySelectorAll('.tab').forEach(function (tab) {
      tab.classList.toggle('is-active', tab.getAttribute('data-slice') === current);
    });
  }

  // ========================================================
  // Karta
  // ========================================================
  function buildCard(rec) {
    var card = document.createElement('article');
    card.className = 'card';
    card.tabIndex = 0;
    card.setAttribute('role', 'button');
    card.setAttribute('aria-label', t('card_detail') + rec.display_name);

    card.appendChild(buildAvatar(rec, 'card-avatar'));

    var body = document.createElement('div');
    body.className = 'card-body';

    var name = document.createElement('div');
    name.className = 'card-name';
    name.textContent = rec.display_name;

    var handle = document.createElement('a');
    handle.className = 'card-handle';
    handle.href = rec.profile_url;
    handle.target = '_blank';
    handle.rel = 'noopener';
    handle.textContent = '@' + rec.id;
    handle.addEventListener('click', function (e) { e.stopPropagation(); });

    body.appendChild(name);
    body.appendChild(handle);
    body.appendChild(buildLabels(rec));
    body.appendChild(buildStats(rec));

    card.appendChild(body);

    // Účet mimo katalog (z vyhledávání) nemá detail → klik vede na profil.
    if (rec._external) {
      card.addEventListener('click', function () { window.open(rec.profile_url, '_blank', 'noopener'); });
    } else {
      card.addEventListener('click', function () { openModal(rec); });
      card.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openModal(rec); }
      });
      if (HOVER_CAPABLE) attachHover(card, rec);
    }

    return card;
  }

  function buildAvatar(rec, cls) {
    var avatar = document.createElement('div');
    avatar.className = cls;
    if (rec.avatar) {
      var img = document.createElement('img');
      img.src = rec.avatar;
      img.alt = '';
      img.loading = 'lazy';
      img.onerror = function () { avatar.classList.add('avatar-fallback'); img.remove(); };
      avatar.appendChild(img);
    } else {
      avatar.classList.add('avatar-fallback');
    }
    return avatar;
  }

  function buildLabels(rec) {
    var labels = document.createElement('div');
    labels.className = 'card-labels';
    if (rec.family) {
      var fam = document.createElement('span');
      fam.className = 'label label-family fam-' + rec.family;
      fam.textContent = familyLabel(rec.family);
      labels.appendChild(fam);
    }
    if (rec.type) {
      var typ = document.createElement('span');
      typ.className = 'label label-type';
      typ.textContent = typeLabel(rec);
      labels.appendChild(typ);
    }
    // Příznak automatizovaného účtu (Mastodon `bot`).
    if (rec.bot === true) {
      var bot = document.createElement('span');
      bot.className = 'label label-bot';
      bot.textContent = '🤖 ' + t('label_bot');
      bot.title = t('label_bot_title');
      labels.appendChild(bot);
    }
    return labels;
  }

  function buildStats(rec) {
    var stats = document.createElement('div');
    stats.className = 'card-stats';
    stats.appendChild(stat(formatNumber(rec.followers), t('stat_followers')));
    stats.appendChild(stat(rec.posts_week == null ? '—' : rec.posts_week, t('stat_posts_week')));
    return stats;
  }

  function stat(value, label) {
    var s = document.createElement('span');
    s.className = 'stat';
    var v = document.createElement('strong');
    v.textContent = value;
    s.appendChild(v);
    s.appendChild(document.createTextNode(' ' + label));
    return s;
  }

  // ========================================================
  // Hover preview
  // ========================================================
  function buildHoverEl() {
    var el = document.createElement('div');
    el.className = 'hover-preview';
    el.hidden = true;
    el.addEventListener('mouseenter', function () { clearTimeout(hoverHideTimer); });
    el.addEventListener('mouseleave', scheduleHoverHide);
    document.body.appendChild(el);
    return el;
  }

  function attachHover(card, rec) {
    card.addEventListener('mouseenter', function () {
      clearTimeout(hoverHideTimer);
      clearTimeout(hoverTimer);
      hoverTimer = setTimeout(function () { showHover(card, rec); }, HOVER_DELAY);
    });
    card.addEventListener('mouseleave', function () {
      clearTimeout(hoverTimer);
      scheduleHoverHide();
    });
  }

  function scheduleHoverHide() {
    clearTimeout(hoverHideTimer);
    hoverHideTimer = setTimeout(function () { hoverEl.hidden = true; }, HOVER_GRACE);
  }

  function showHover(card, rec) {
    hoverEl.innerHTML = '';

    var head = document.createElement('div');
    head.className = 'hover-head';
    head.appendChild(buildAvatar(rec, 'hover-avatar'));
    var ht = document.createElement('div');
    var hn = document.createElement('div');
    hn.className = 'hover-name';
    hn.textContent = rec.display_name;
    var hh = document.createElement('div');
    hh.className = 'hover-handle';
    hh.textContent = '@' + rec.id;
    ht.appendChild(hn);
    ht.appendChild(hh);
    head.appendChild(ht);
    hoverEl.appendChild(head);

    if (rec.bio) {
      var bio = document.createElement('div');
      bio.className = 'hover-bio';
      bio.appendChild(sanitizeBio(rec.bio));
      hoverEl.appendChild(bio);
    }

    var meta = document.createElement('div');
    meta.className = 'hover-meta';
    meta.appendChild(metaLine(platformsText(rec)));
    var added = relAdded(rec.created_at);
    if (added) meta.appendChild(metaLine(added));
    hoverEl.appendChild(meta);

    hoverEl.hidden = false;
    positionHover(card);
  }

  function positionHover(card) {
    var r = card.getBoundingClientRect();
    var pw = hoverEl.offsetWidth, ph = hoverEl.offsetHeight;
    var gap = 8;
    var left = r.left;
    var top = r.bottom + gap;
    if (top + ph > window.innerHeight && r.top - ph - gap > 0) top = r.top - ph - gap;
    if (left + pw > window.innerWidth - 8) left = window.innerWidth - pw - 8;
    if (left < 8) left = 8;
    hoverEl.style.left = (left + window.scrollX) + 'px';
    hoverEl.style.top = (top + window.scrollY) + 'px';
  }

  function metaLine(text) {
    var p = document.createElement('div');
    p.className = 'meta-line';
    p.textContent = text;
    return p;
  }

  function platformsText(rec) {
    var ps = (rec.source_platforms || []).map(platformLabel);
    return t('hover_source') + (ps.length ? ps.join(', ') : '—');
  }

  // ========================================================
  // Detail modal (<dialog>)
  // ========================================================
  function openModal(rec) {
    hoverEl.hidden = true;
    clearTimeout(hoverTimer);
    modalEl.innerHTML = '';
    modalEl.appendChild(buildModalContent(rec));
    if (typeof modalEl.showModal === 'function') {
      modalEl.showModal();
    } else {
      modalEl.setAttribute('open', '');  // fallback: position:fixed overlay přes CSS
      modalEl.classList.add('modal-fallback-open');
    }
  }

  function closeModal() {
    if (typeof modalEl.close === 'function' && modalEl.open) modalEl.close();
    modalEl.removeAttribute('open');
    modalEl.classList.remove('modal-fallback-open');
  }

  function bindModalClose() {
    // Klik mimo obsah (na backdrop dialogu)
    modalEl.addEventListener('click', function (e) {
      if (e.target === modalEl) closeModal();
    });
    // Escape u <dialog> ruší nativně přes 'cancel'
    modalEl.addEventListener('cancel', function () { closeModal(); });
    modalEl.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') { e.preventDefault(); closeModal(); }
    });
  }

  function buildModalContent(rec) {
    var wrap = document.createElement('div');
    wrap.className = 'modal-inner';

    var close = document.createElement('button');
    close.className = 'modal-close';
    close.setAttribute('aria-label', t('modal_close'));
    close.innerHTML = '';
    close.textContent = '×';
    close.addEventListener('click', closeModal);
    wrap.appendChild(close);

    var head = document.createElement('div');
    head.className = 'modal-head';
    head.appendChild(buildAvatar(rec, 'modal-avatar'));
    var ht = document.createElement('div');
    ht.className = 'modal-headtext';
    var hn = document.createElement('div');
    hn.className = 'modal-name';
    hn.textContent = rec.display_name;
    var hh = document.createElement('a');
    hh.className = 'modal-handle';
    hh.href = rec.profile_url;
    hh.target = '_blank';
    hh.rel = 'noopener';
    hh.textContent = '@' + rec.id;
    ht.appendChild(hn);
    ht.appendChild(hh);
    head.appendChild(ht);
    wrap.appendChild(head);

    if (rec.bio) {
      var bio = document.createElement('div');
      bio.className = 'modal-bio';
      bio.appendChild(sanitizeBio(rec.bio));
      wrap.appendChild(bio);
    }

    wrap.appendChild(buildLabels(rec));

    if (rec.categories && rec.categories.length) {
      var cats = document.createElement('div');
      cats.className = 'modal-tags';
      rec.categories.forEach(function (cat) {
        var chip = document.createElement('button');
        chip.className = 'tag-chip';
        chip.textContent = cat;
        chip.addEventListener('click', function () {
          closeModal();
          if (isTopSlice()) slice = { kind: 'all' };
          filters.tag.add(cat);
          render();
        });
        cats.appendChild(chip);
      });
      wrap.appendChild(cats);
    }

    var stats = document.createElement('div');
    stats.className = 'modal-stats';
    stats.appendChild(modalStat(formatNumber(rec.followers), t('stat_followers')));
    stats.appendChild(modalStat(rec.posts_week == null ? '—' : formatNumber(rec.posts_week), t('stat_posts_week')));
    stats.appendChild(modalStat(langLabel(rec.language), t('stat_language')));
    var added = relAdded(rec.created_at);
    if (added) stats.appendChild(modalStat('', added, true));
    wrap.appendChild(stats);

    var actions = document.createElement('div');
    actions.className = 'modal-actions';
    var profile = document.createElement('a');
    profile.className = 'btn btn-primary';
    profile.href = rec.profile_url;
    profile.target = '_blank';
    profile.rel = 'noopener';
    profile.textContent = t('modal_open');
    actions.appendChild(profile);
    var follow = document.createElement('a');
    follow.className = 'btn btn-ghost';
    // Odkaz vede na profil účtu — Mastodon tam ukáže dialog „Sledovat", který
    // návštěvníka nechá zadat VLASTNÍ instanci (ne přihlášení na zpravobot.news).
    follow.href = rec.profile_url;
    follow.target = '_blank';
    follow.rel = 'noopener';
    follow.title = t('modal_follow_title');
    follow.textContent = t('modal_follow');
    actions.appendChild(follow);
    wrap.appendChild(actions);

    return wrap;
  }

  function modalStat(value, label, labelOnly) {
    var s = document.createElement('div');
    s.className = 'modal-stat';
    if (labelOnly) {
      s.classList.add('modal-stat-wide');
      s.textContent = label;
      return s;
    }
    var v = document.createElement('strong');
    v.textContent = value;
    var l = document.createElement('span');
    l.textContent = label;
    s.appendChild(v);
    s.appendChild(l);
    return s;
  }

  // ========================================================
  // Sanitizace bio (HTML z Mastodon note → whitelist a/br/p/span)
  // ========================================================
  function sanitizeBio(html) {
    var allowed = { A: 1, BR: 1, P: 1, SPAN: 1 };
    var doc = new DOMParser().parseFromString(String(html), 'text/html');
    var frag = document.createDocumentFragment();
    walkNodes(doc.body, frag, allowed);
    return frag;
  }

  function walkNodes(src, dest, allowed) {
    Array.prototype.forEach.call(src.childNodes, function (node) {
      if (node.nodeType === 3) {
        dest.appendChild(document.createTextNode(node.nodeValue));
        return;
      }
      if (node.nodeType !== 1) return;
      var tag = node.tagName;
      if (!allowed[tag]) { walkNodes(node, dest, allowed); return; }  // unwrap
      var el = document.createElement(tag.toLowerCase());
      if (tag === 'A') {
        var href = node.getAttribute('href') || '';
        if (/^https?:\/\//i.test(href)) {
          el.setAttribute('href', href);
          el.target = '_blank';
          el.rel = 'noopener noreferrer';
        }
      }
      walkNodes(node, el, allowed);
      dest.appendChild(el);
    });
  }

  // Sanitizace obsahu postu (Mastodon `content`): whitelist a/br/p/span.
  // Hashtagy (a.hashtag) → interní filtr; mentions (a.mention) a běžné odkazy
  // → externí (target=_blank). `.invisible`/`.ellipsis` třídy zachováme kvůli
  // zkracování URL, jak to dělá Mastodon.
  function sanitizePostHtml(html) {
    var doc = new DOMParser().parseFromString(String(html), 'text/html');
    var frag = document.createDocumentFragment();
    walkPostNodes(doc.body, frag);
    return frag;
  }

  function walkPostNodes(src, dest) {
    var allowed = { A: 1, BR: 1, P: 1, SPAN: 1 };
    Array.prototype.forEach.call(src.childNodes, function (node) {
      if (node.nodeType === 3) {
        dest.appendChild(document.createTextNode(node.nodeValue));
        return;
      }
      if (node.nodeType !== 1) return;
      var tag = node.tagName;
      if (!allowed[tag]) { walkPostNodes(node, dest); return; }
      var el = document.createElement(tag.toLowerCase());

      if (tag === 'SPAN') {
        // Zachovat Mastodon třídy pro zkrácené URL (invisible/ellipsis).
        var cls = node.getAttribute('class') || '';
        if (/\b(invisible|ellipsis)\b/.test(cls)) el.className = cls;
      }

      if (tag === 'A') {
        var href = node.getAttribute('href') || '';
        var aClass = node.getAttribute('class') || '';
        var isHashtag = /\bhashtag\b/.test(aClass) ||
                        /\/tags\//.test(href);
        if (isHashtag) {
          // Hashtag → interní filtr (ne odkaz pryč).
          var tagName = node.textContent.replace(/^#/, '').trim().toLowerCase();
          el.className = 'post-inline-hashtag';
          el.setAttribute('href', '#');
          el.setAttribute('role', 'button');
          el.addEventListener('click', function (ev) {
            ev.preventDefault();
            togglePostHashtag(tagName);
          });
        } else if (/^https?:\/\//i.test(href)) {
          el.className = /\bmention\b/.test(aClass) ? 'post-inline-mention' : 'post-inline-link';
          el.setAttribute('href', href);
          el.target = '_blank';
          el.rel = 'noopener noreferrer';
        }
      }
      walkPostNodes(node, el);
      dest.appendChild(el);
    });
  }

  // ========================================================
  // URL hash state
  // ========================================================
  function writeHash() {
    var parts = [];
    if (filters.family.size) parts.push('family=' + enc(setList(filters.family)));
    if (filters.type.size) parts.push('type=' + enc(setList(filters.type)));
    if (filters.language.size) parts.push('lang=' + enc(setList(filters.language)));
    if (filters.tag.size) parts.push('tag=' + enc(setList(filters.tag)));
    if (searchQuery) parts.push('q=' + enc(searchQuery));
    if (sortKey !== 'name') parts.push('sort=' + enc(sortKey));
    if (slice.kind !== 'all') parts.push('slice=' + enc(sliceToString(slice)));
    if (view === 'about') {
      parts.push('view=about');
      if (aboutSection !== 'about') parts.push('asec=' + aboutSection);
    } else if (view === 'search') {
      parts.push('view=search');
      if (searchQEl && searchQEl.value.trim()) parts.push('sq=' + enc(searchQEl.value.trim()));
      if (searchTab !== 'all') parts.push('stab=' + searchTab);
      if (postHashtags.size) parts.push('phash=' + enc(setList(postHashtags)));
    } else if (view === 'instance') {
      parts.push('view=instance');
      if (instanceTab !== 'all') parts.push('itab=' + instanceTab);
      if (instanceCats.size) parts.push('icat=' + enc(setList(instanceCats)));
    } else if (view === 'odkazy') {
      parts.push('view=odkazy');
      if (linkTypes.size) parts.push('ltype=' + enc(setList(linkTypes)));
      if (linkLangs.size) parts.push('llang=' + enc(setList(linkLangs)));
    } else if (view === 'posty') {
      parts.push('view=posty');
      if (postsSort !== 'engagement') parts.push('psort=' + enc(postsSort));
      if (postsTab !== 'all') parts.push('ptab=' + postsTab);
      if (postHashtags.size) parts.push('phash=' + enc(setList(postHashtags)));
    }
    var hash = parts.join('&');
    suppressHash = true;
    if (hash) {
      if (location.hash.slice(1) !== hash) location.hash = hash;
    } else if (location.hash) {
      history.replaceState(null, '', location.pathname + location.search);
    }
    setTimeout(function () { suppressHash = false; }, 0);
  }

  function parseHash() {
    pendingAccountId = null;
    var hash = location.hash.replace(/^#/, '');
    if (!hash) return;
    filters.family.clear(); filters.type.clear();
    filters.language.clear(); filters.tag.clear();
    searchQuery = ''; sortKey = 'name'; slice = { kind: 'all' };
    view = 'ucty'; postsSort = 'engagement'; postsTab = 'all'; aboutSection = 'about'; postHashtags.clear();
    instanceTab = 'all'; searchTab = 'all'; instanceCats.clear(); pendingSearchQ = '';
    linkTypes.clear(); linkLangs.clear();

    hash.split('&').forEach(function (pair) {
      // Holé tokeny bez "=" (např. starší #posty / #ucty) → přepínač pohledu.
      if (/^(posty|ucty|about|search|instance|odkazy)$/.test(pair)) { view = pair; return; }
      var i = pair.indexOf('=');
      if (i === -1) return;
      var key = pair.slice(0, i);
      var val = dec(pair.slice(i + 1));
      switch (key) {
        case 'family': splitList(val).forEach(function (v) { filters.family.add(v); }); break;
        case 'type': splitList(val).forEach(function (v) { filters.type.add(v); }); break;
        case 'lang': splitList(val).forEach(function (v) { filters.language.add(v); }); break;
        case 'tag': splitList(val).forEach(function (v) { filters.tag.add(v); }); break;
        case 'q': searchQuery = val.toLowerCase(); break;
        case 'sort': if (/^(name|followers|posts|added)$/.test(val)) sortKey = val; break;
        case 'slice': slice = parseSlice(val); break;
        case 'account': pendingAccountId = val; break;
        case 'view': if (/^(posty|ucty|about|search|instance|odkazy)$/.test(val)) view = val; break;
        case 'sq': pendingSearchQ = val; break;
        case 'psort': if (/^(engagement|reblogs|favourites|date|date_asc)$/.test(val)) postsSort = val; break;
        case 'ptab': if (/^(all|10|50|risers_ratio|risers_abs)$/.test(val)) postsTab = val; break;
        case 'itab': if (/^(all|10|50|ratio|volume)$/.test(val)) instanceTab = val; break;
        case 'icat': splitList(val).forEach(function (v) { instanceCats.add(v); }); break;
        case 'ltype': splitList(val).forEach(function (v) { linkTypes.add(v); }); break;
        case 'llang': splitList(val).forEach(function (v) { linkLangs.add(v); }); break;
        case 'stab': if (/^(all|10|50|risers_ratio|risers_abs)$/.test(val)) searchTab = val; break;
        case 'asec': if (/^(about|search|instance|accounts|posts|links|tech|author|faq)$/.test(val)) aboutSection = val; break;
        case 'phash': splitList(val).forEach(function (v) { postHashtags.add(v); }); break;
      }
    });
  }

  // Otevře modal účtu odkazovaného přes #account=<id> (per-účet sdílecí stub).
  function maybeOpenPendingAccount() {
    if (!pendingAccountId) return;
    var id = pendingAccountId;
    pendingAccountId = null;
    for (var i = 0; i < records.length; i++) {
      if (records[i].id === id) { openModal(records[i]); return; }
    }
  }

  function onHashChange() {
    if (suppressHash) return;
    parseHash();
    applyStateToControls();
    render();
    maybeOpenPendingAccount();
  }

  // Promítne stav (z hashe) do ovládacích prvků v sidebaru.
  function applyStateToControls() {
    document.querySelectorAll('.filter-group button[data-value]').forEach(function (btn) {
      var section = btn.closest('.filter-group').getAttribute('data-filter');
      var set = filters[section];
      btn.classList.toggle('active', !!(set && set.has(btn.getAttribute('data-value'))));
    });
    // Filtry Odkazů (data-ltype / data-llang) podle stavu z hashe.
    document.querySelectorAll('#links-type-group button[data-ltype]').forEach(function (btn) {
      btn.classList.toggle('active', linkTypes.has(btn.getAttribute('data-ltype')));
    });
    document.querySelectorAll('#links-lang-group button[data-llang]').forEach(function (btn) {
      btn.classList.toggle('active', linkLangs.has(btn.getAttribute('data-llang')));
    });
    searchEl.value = searchQuery;
    sortEl.value = sortKey;
    if (postsSortEl) postsSortEl.value = postsSort;
    if (searchQEl) searchQEl.value = pendingSearchQ || '';
    applyView();  // applyView volá updatePostsTabsUI() / renderSearch()
  }

  // ========================================================
  // Slice (de)serializace
  // ========================================================
  function parseSlice(str) {
    if (!str || str === 'all') return { kind: 'all' };
    var p = str.split(':');
    if (p[0] === 'platform') return { kind: 'platform', value: p[1] };
    if (p[0] === 'recent') return { kind: 'recent' };
    if (p[0] === 'top') return { kind: 'top', metric: p[1], count: parseInt(p[2], 10) || 10 };
    return { kind: 'all' };
  }

  function sliceToString(s) {
    if (s.kind === 'platform') return 'platform:' + s.value;
    if (s.kind === 'recent') return 'recent';
    if (s.kind === 'top') return 'top:' + s.metric + ':' + s.count;
    return 'all';
  }

  // ========================================================
  // Reset
  // ========================================================
  function resetAll() {
    filters.family.clear(); filters.type.clear();
    filters.language.clear(); filters.tag.clear();
    searchQuery = ''; searchEl.value = '';
    sortKey = 'name'; sortEl.value = 'name';
    slice = { kind: 'all' };
    tagInputEl.value = '';
    document.querySelectorAll('.filter-group button.active')
      .forEach(function (b) { b.classList.remove('active'); });
    render();
  }

  // ========================================================
  // Datum / čas
  // ========================================================
  function daysSince(iso) {
    if (!iso) return null;
    var then = new Date(iso + 'T00:00:00');
    if (isNaN(then.getTime())) return null;
    return Math.floor((Date.now() - then.getTime()) / 86400000);
  }

  // Aktivní účet = poslední příspěvek do ACTIVE_DAYS dní. Bez údaje (null =
  // nikdy nepostnul) → neaktivní/skrytý; jakmile postne, refresh doplní datum
  // a účet se zase objeví.
  function isActive(r) {
    var d = daysSince(r.last_status_at);
    return d !== null && d <= ACTIVE_DAYS;
  }

  function plural(n, one, few, many) {
    if (n === 1) return one;
    if (n >= 2 && n <= 4) return few;
    return many;
  }

  // "přidán před X" / "added X ago" — větvíme podle jazyka (čeština má složitější
  // skloňování než angličtina).
  function relAdded(iso) {
    var d = daysSince(iso);
    if (d === null) return '';
    if (lang === 'en') {
      if (d <= 0) return 'added today';
      if (d === 1) return 'added yesterday';
      if (d < 31) return 'added ' + d + ' days ago';
      var em = Math.round(d / 30);
      if (em < 12) return 'added ' + em + (em === 1 ? ' month ago' : ' months ago');
      var ey = Math.round(d / 365);
      return 'added ' + ey + (ey === 1 ? ' year ago' : ' years ago');
    }
    if (d <= 0) return 'přidán dnes';
    if (d === 1) return 'přidán včera';
    if (d < 31) return 'přidán před ' + d + ' ' + plural(d, 'dnem', 'dny', 'dny');
    var m = Math.round(d / 30);
    if (m < 12) return 'přidán před ' + m + ' ' + plural(m, 'měsícem', 'měsíci', 'měsíci');
    var y = Math.round(d / 365);
    return 'přidán před ' + y + ' ' + plural(y, 'rokem', 'lety', 'lety');
  }

  // Čas posledního buildu vyhledávacího indexu z malého status.json (mění se denně).
  function renderSearchIndexed() {
    fetch('status.json', { cache: 'no-cache' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (s) {
        if (!s || !s.search_indexed) return;
        var d = new Date(s.search_indexed);
        if (isNaN(d.getTime())) return;
        var el = document.getElementById('indexed-date');
        var wrap = document.getElementById('footer-indexed');
        if (!el || !wrap) return;
        var mm = d.getMinutes() < 10 ? '0' + d.getMinutes() : d.getMinutes();
        el.textContent = d.getDate() + '. ' + (d.getMonth() + 1) + '. ' + d.getFullYear() + ' ' + d.getHours() + ':' + mm;
        wrap.hidden = false;
      })
      .catch(function () {});
  }

  function renderUpdatedRelative() {
    var el = document.getElementById('updated-relative');
    if (!el) return;
    var iso = document.body.getAttribute('data-updated');
    var d = daysSince(iso);
    if (d === null) return;
    var txt;
    if (lang === 'en') {
      txt = d <= 0 ? '(today)' : d === 1 ? '(yesterday)' : '(' + d + ' days ago)';
    } else if (d <= 0) {
      txt = '(dnes)';
    } else if (d === 1) {
      txt = '(včera)';
    } else {
      txt = '(před ' + d + ' ' + plural(d, 'dnem', 'dny', 'dny') + ')';
    }
    el.textContent = ' ' + txt;
  }

  // ========================================================
  // Utils
  // ========================================================
  function formatNumber(n) {
    return String(n == null ? 0 : n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  }
  function setList(set) { return Array.from(set).join(','); }
  function splitList(s) { return s.split(',').filter(Boolean); }
  function enc(s) { return encodeURIComponent(s); }
  function dec(s) { try { return decodeURIComponent(s); } catch (e) { return s; } }
})();
