# frozen_string_literal: true

# lib/paths.rb — kořenové kotvení cest projektu.
#
# Díky tomuto modulu nezáleží, odkud se skript pouští ani kde leží — všechny
# config/data/web cesty se odvozují od kořene projektu (o úroveň výš než lib/).
# Skripty tak mohou být v bin/ a přitom spolehlivě najdou config/, data/, web/.
module Paths
  ROOT       = File.expand_path("..", __dir__) # lib/ → kořen projektu
  BIN_DIR    = File.join(ROOT, "bin")
  CONFIG_DIR = File.join(ROOT, "config")
  DATA_DIR   = File.join(ROOT, "data")
  WEB_DIR    = File.join(ROOT, "web")
  DOCS_DIR   = File.join(ROOT, "docs")
  LOGS_DIR   = File.join(ROOT, "logs")
  CONFIG_ENV = File.join(ROOT, "config.env") # tajemství; mimo git, jen na serveru

  # Katalog má dvě podoby a je důležité je neplést:
  #   CATALOG_STORE  — interní úložiště, PLNÉ záznamy (mastodon_id pro pipeline,
  #                    _ai_description, stav ověření…). Čte a zapisuje pipeline.
  #   CATALOG_PUBLIC — co se publikuje na web a stahuje každý návštěvník: jen pole,
  #                    která frontend opravdu vykresluje, kompaktní JSON.
  # Historicky to byl jeden soubor (web/data.json), takže se do prohlížečů posílala
  # i interní pole. Skripty čtou store a padají zpět na public (migrace starých
  # instalací, kde store ještě nevznikl).
  CATALOG_STORE  = File.join(DATA_DIR, "catalog.json")
  CATALOG_PUBLIC = File.join(WEB_DIR, "data.json")

  # Cesta ke katalogu ke ČTENÍ: store, dokud existuje, jinak publikovaná verze.
  def self.catalog_source
    File.exist?(CATALOG_STORE) ? CATALOG_STORE : CATALOG_PUBLIC
  end
end
