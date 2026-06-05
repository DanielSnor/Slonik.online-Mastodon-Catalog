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
  ARCHIV_DIR = File.join(ROOT, "archiv")
  CONFIG_ENV = File.join(ROOT, "config.env") # tajemství; mimo git, jen na serveru
end
