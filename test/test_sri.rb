# frozen_string_literal: true

require_relative "helper"

load_script("../bin/check_sri.rb")

# Parser externích zdrojů. Chyba tady se projeví buď planým poplachem každý
# týden (a přestane se na hlášení koukat), nebo tím, že hlídač mlčí, i když
# otisk dávno nesedí.
class TestSubresourceParser < Minitest::Test
  def test_finds_external_script_with_integrity
    out = external_subresources(%(<script defer src="https://cdn.example/x.js" integrity="sha384-AAA" crossorigin="anonymous"></script>))
    assert_equal 1, out.size
    assert_equal "https://cdn.example/x.js", out.first[:url]
    assert_equal "sha384-AAA", out.first[:integrity]
  end

  def test_reports_external_script_without_integrity
    out = external_subresources(%(<script src="https://cdn.example/x.js"></script>))
    assert_equal 1, out.size
    assert_nil out.first[:integrity]
  end

  # Tohle je ta past: canonical a hreflang alternate jsou <link> na absolutní
  # https adresu, ale nic se z nich nestahuje ani nespouští. Původní verze je
  # hlásila jako „externí skript bez integrity" — čtyři plané poplachy týdně.
  def test_metadata_links_are_not_subresources
    html = <<~HTML
      <link rel="canonical" href="https://slonik.online/">
      <link rel="alternate" hreflang="en" href="https://slonik.online/?lang=en">
      <link rel="icon" href="https://slonik.online/favicon.ico">
    HTML
    assert_empty external_subresources(html)
  end

  def test_stylesheets_and_preloads_are_subresources
    html = <<~HTML
      <link rel="stylesheet" href="https://cdn.example/a.css">
      <link rel="preload" as="font" href="https://cdn.example/f.woff2">
      <link rel="modulepreload" href="https://cdn.example/m.js">
    HTML
    assert_equal 3, external_subresources(html).size
  end

  def test_relative_and_local_sources_are_ignored
    html = <<~HTML
      <script src="app.js"></script>
      <link rel="stylesheet" href="app.css">
      <script src="http://insecure.example/x.js"></script>
    HTML
    assert_empty external_subresources(html), "hlídáme jen absolutní https zdroje"
  end

  def test_single_quotes_are_handled
    out = external_subresources(%(<script src='https://cdn.example/x.js' integrity='sha384-BBB'></script>))
    assert_equal "sha384-BBB", out.first[:integrity]
  end
end

class TestIntegrityMatching < Minitest::Test
  DATA = "console.log('ahoj')"

  def sri(algo) = sri_digest(algo, DATA)

  def test_matching_hash_passes
    ok, = integrity_matches?(sri("sha384"), DATA)
    assert ok
  end

  def test_changed_content_fails
    ok, = integrity_matches?(sri("sha384"), "#{DATA} // upgrade")
    refute ok, "změněný obsah nesmí projít — přesně tohle se stane po upgradu služby"
  end

  # SRI atribut smí nést víc otisků; stačí shoda s jedním.
  def test_any_of_several_hashes_is_enough
    ok, = integrity_matches?("sha256-cizi #{sri('sha384')}", DATA)
    assert ok
  end

  def test_all_supported_algorithms
    %w[sha256 sha384 sha512].each do |algo|
      ok, = integrity_matches?(sri(algo), DATA)
      assert ok, "#{algo} musí být podporováno"
    end
  end

  def test_unknown_algorithm_does_not_pass_silently
    ok, = integrity_matches?("md5-cokoliv", DATA)
    refute ok
  end

  def test_digest_format_is_algo_dash_base64
    assert_match(%r{\Asha384-[A-Za-z0-9+/]+={0,2}\z}, sri("sha384"))
  end
end
