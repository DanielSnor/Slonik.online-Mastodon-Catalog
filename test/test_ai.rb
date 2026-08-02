# frozen_string_literal: true

require_relative "helper"
require_relative "../lib/ai"

# Klasifikace: mapování rodin a normalizace odpovědi modelu. Právě tady vznikla
# chyba, kvůli které polovina katalogu skončila v koši „lifestyle" — model rodinu
# `local` vracel, ale FAMILY_MAP na ni neměl klíč, takže spadla na fallback.
class TestAI < Minitest::Test
  def setup
    @ai = AI.new
  end

  def test_every_family_the_model_can_return_has_a_mapping
    AI::FAMILIES.each do |f|
      refute_nil AI::FAMILY_MAP[f], "FAMILY_MAP nemá klíč pro rodinu #{f.inspect}"
    end
  end

  def test_mapping_targets_are_known_catalog_families
    AI::FAMILY_MAP.each_value do |target|
      assert_includes AI::VALID_CATALOG_FAMILIES, target
    end
  end

  def test_local_is_not_swallowed_by_the_lifestyle_bucket
    assert_equal "local", @ai.map_family("local")
    assert_equal "lifestyle", @ai.map_family("other")
    refute_equal @ai.map_family("local"), @ai.map_family("other"),
                 "regionální účty musí jít odlišit od nezařaditelných"
  end

  def test_nature_has_its_own_family_and_is_not_science
    assert_equal "nature", @ai.map_family("nature")
    refute_equal @ai.map_family("nature"), @ai.map_family("tech"),
                 "včelař ani zahrádkář nepatří pod „věda a technika“"
  end

  # Dva few-shot příklady dřív ukazovaly rodiny katalogu ("government",
  # "science_tech") místo hodnot z FAMILIES. Model je napodobil, normalize je
  # srazil na "other" a účet tiše spadl do koše. Načtení AI to teď zvedne.
  def test_prompt_examples_use_only_valid_families
    shown = AI::SYSTEM_PROMPT.scan(/"family":\s*"([^"]+)"/).flatten
                             .reject { |f| f == "..." }.uniq
    refute_empty shown, "prompt by měl obsahovat few-shot příklady"
    assert_empty shown - AI::FAMILIES,
                 "příklady smí ukazovat jen rodiny z FAMILIES, ne rodiny katalogu"
  end

  def test_every_family_maps_to_a_catalog_family
    assert_empty AI::FAMILY_MAP.values.uniq - AI::VALID_CATALOG_FAMILIES
    assert_empty AI::FAMILIES - AI::FAMILY_MAP.keys
  end

  def test_unknown_family_falls_back
    assert_equal "lifestyle", @ai.map_family("neco-co-model-vymyslel")
    assert_equal "lifestyle", @ai.map_family(nil)
  end

  def test_map_family_is_case_and_whitespace_tolerant
    assert_equal "science_tech", @ai.map_family("  TECH ")
  end

  def test_normalize_sanitizes_tags
    out = @ai.normalize("family" => "tech", "type" => "person",
                        "tags" => ["Software Developer", "OPEN SOURCE", "self-hosting", "", "a b", "x", "y", "z"],
                        "description" => "  popis  ")
    assert_equal %w[software_developer open_source selfhosting a_b x], out["tags"], "max 5, lowercase, bez interpunkce"
    assert_equal "popis", out["description"]
  end

  def test_normalize_falls_back_on_invalid_values
    out = @ai.normalize("family" => "vymyslena", "type" => "vymysleny", "tags" => nil, "description" => nil)
    assert_equal "other", out["family"]
    assert_equal AI::DEFAULT_TYPE, out["type"]
    assert_empty out["tags"]
  end

  def test_parse_json_survives_what_models_wrap_around_json
    expected = { "family" => "tech" }
    assert_equal expected, @ai.parse_json('{"family": "tech"}')
    assert_equal expected, @ai.parse_json("```json\n{\"family\": \"tech\"}\n```")
    assert_equal expected, @ai.parse_json("Jistě! {\"family\": \"tech\"} — snad pomůže.")
    assert_nil @ai.parse_json("bez jsonu")
    assert_nil @ai.parse_json("{rozbity json")
  end
end
