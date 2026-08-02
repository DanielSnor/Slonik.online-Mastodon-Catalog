# frozen_string_literal: true

require_relative "helper"
require_relative "../lib/catalog"
require_relative "../lib/config"
require "tmpdir"

# Co se publikuje na web a co zůstává v úložišti. Chyba tady není vidět v kódu —
# projeví se až tím, že prohlížeče stahují pole, která neměly dostat.
class TestCatalogPublish < Minitest::Test
  def rec
    { "id" => "a@x.cz", "display_name" => "A", "avatar" => "https://x.cz/a.png",
      "avatar_local" => "avatars/abc123def456.webp", "mastodon_id" => "123",
      "_ai_description" => "strojový popis konkrétního člověka",
      "source_details" => [{ "platform" => "mastodon" }],
      "last_verified_at" => "2026-08-02", "unverified_since" => "2026-01-01",
      "verify_failures" => 3 }
  end

  def test_internal_fields_never_reach_the_public_payload
    out = Catalog.slim([rec]).first
    %w[mastodon_id _ai_description source_details last_verified_at unverified_since
       verify_failures].each do |k|
      refute out.key?(k), "#{k} nemá co dělat v publikovaném katalogu"
    end
  end

  def test_displayed_fields_survive
    out = Catalog.slim([rec]).first
    %w[id display_name avatar avatar_local].each { |k| assert out.key?(k) }
  end

  def test_public_keys_cover_what_the_frontend_renders
    %w[id display_name type family language categories avatar avatar_local bio
       followers posts_week created_at last_status_at profile_url source_platforms
       bot followers_delta activity_delta].each do |k|
      assert_includes Catalog::PUBLIC_KEYS, k
    end
  end

  def test_publish_writes_compact_json
    Dir.mktmpdir do |dir|
      path = File.join(dir, "data.json")
      Catalog.publish([rec], path)
      raw = File.read(path, encoding: "UTF-8")
      refute_includes raw, "\n  ", "publikovaný payload nemá být pretty-printed"
      assert_equal 1, JSON.parse(raw).size
    end
  end

  def test_write_json_is_atomic_and_leaves_no_temp_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "store.json")
      Catalog.write_json(path, [rec])
      assert_equal [rec], Catalog.load(path)
      refute File.exist?("#{path}.tmp")
    end
  end
end

# Cesty na Surferu — avatary jdou do podsložky, ostatní data do kořene.
class TestSurferPaths < Minitest::Test
  def with_remote_dir(value)
    old = ENV["SURFER_REMOTE_DIR"]
    ENV["SURFER_REMOTE_DIR"] = value
    yield
  ensure
    ENV["SURFER_REMOTE_DIR"] = old
  end

  def test_root_deployment
    with_remote_dir("") do
      assert_equal "data.json", Surfer.remote_path("data.json")
      assert_equal "avatars/ab.webp", Surfer.remote_path("ab.webp", subdir: "avatars")
    end
  end

  def test_subfolder_deployment
    with_remote_dir("slonik-test") do
      assert_equal "slonik-test/data.json", Surfer.remote_path("data.json")
      assert_equal "slonik-test/avatars/ab.webp", Surfer.remote_path("ab.webp", subdir: "avatars")
    end
  end

  def test_slashes_are_normalized
    with_remote_dir("/dir/") do
      assert_equal "dir/avatars/ab.webp", Surfer.remote_path("ab.webp", subdir: "/avatars/")
    end
  end
end
