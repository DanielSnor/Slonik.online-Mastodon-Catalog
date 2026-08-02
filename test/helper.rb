# frozen_string_literal: true

# Společný základ testů. Bez gemů — minitest je součástí Ruby.
#
# Testy schválně nesahají na síť ani na produkční data: pokrývají čisté funkce,
# tedy místa, kde se tichá chyba projeví až jako křivá čísla na webu.

require "minitest/autorun"

# Skripty v bin/ se dají načíst bez spuštění (mají `main if __FILE__ == $PROGRAM_NAME`),
# ale čtou ARGV a ENV. Testovací runner si předává vlastní argumenty, takže je
# schováme — jinak by `--name` z minitestu vypadalo jako neznámý flag.
def load_script(relative)
  argv = ARGV.dup
  ARGV.clear
  load File.expand_path(relative, __dir__)
ensure
  ARGV.replace(argv)
end
