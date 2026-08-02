#!/usr/bin/env ruby
# frozen_string_literal: true

# Spustí testy z test/. Bez gemů — minitest je součástí Ruby.
#
#   ruby bin/run_tests.rb          # vše
#   ruby bin/run_tests.rb posts    # jen test/test_posts.rb
#
# Testy nesahají na síť ani na produkční data; pokrývají čisté funkce, tedy
# místa, kde se tichá chyba projeví až jako křivá čísla na webu.
#
# Každý soubor běží ve VLASTNÍM procesu: testy načítají skripty z bin/, a ty
# definují konstanty stejných jmen (DRY_RUN…). Ve sdíleném procesu by se
# přepisovaly — nejen hluk ve výpisu, ale i riziko, že test uvidí cizí hodnotu.

require "rbconfig"
require_relative "../lib/paths"

filter  = ARGV.shift
pattern = filter ? "test_*#{filter}*.rb" : "test_*.rb"
files   = Dir[File.join(Paths::ROOT, "test", pattern)].sort

abort("❌ Žádné testy neodpovídají #{pattern}") if files.empty?

ruby = RbConfig.ruby
failed = files.reject do |f|
  puts "── #{File.basename(f)}"
  system(ruby, f)
end

puts
if failed.empty?
  puts "✅ Všechny testy prošly (#{files.size} souborů)"
  exit 0
else
  puts "❌ Selhalo: #{failed.map { |f| File.basename(f) }.join(', ')}"
  exit 1
end
