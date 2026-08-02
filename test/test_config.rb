# frozen_string_literal: true

require_relative "helper"
require_relative "../lib/config"
require "tmpdir"

class TestConfigLists < Minitest::Test
  def with_list(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "list.txt")
      File.write(path, content)
      ENV["TEST_LIST_FILE"] = path
      yield path
    ensure
      ENV.delete("TEST_LIST_FILE")
    end
  end

  def test_read_list_drops_comments_and_blanks
    with_list("# komentář\n\nprvni.cz\n  druha.cz  # koncový komentář\n\n") do
      assert_equal %w[prvni.cz druha.cz], CatalogConfig.read_list("list.txt", env_key: "TEST_LIST_FILE")
    end
  end

  def test_read_list_of_missing_file_is_empty
    assert_empty CatalogConfig.read_list("rozhodne-neexistuje.txt")
  end

  # Mastodon handle je case-insensitive. Když se blocklist porovnával přesně,
  # záznam zapsaný jinou velikostí písmen tiše neudělal nic — tedy nevyřízená
  # žádost o odstranění, která vypadá jako vyřízená.
  def test_handle_set_is_lowercased
    with_list("Franta@Example.CZ\nnekdo@jiny.cz\n") do
      set = CatalogConfig.read_handle_set("list.txt", env_key: "TEST_LIST_FILE")
      assert_includes set, "franta@example.cz"
      assert_includes set, "nekdo@jiny.cz"
      assert_equal 2, set.size
    end
  end
end

# Upload skládá multipart tělo jako stream, ať se soubor nedrží celý v paměti.
# Musí ale vyrobit přesně stejné bajty jako dřív a snést všechny způsoby čtení,
# které Net::HTTP může použít.
class TestMultipartStream < Minitest::Test
  PRE = "--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"d.json\"\r\n\r\n"
  EPI = "\r\n--B--\r\n"

  def with_payload
    Dir.mktmpdir do |dir|
      path = File.join(dir, "d.json")
      # Záměrně obsah s diakritikou i binárním bajtem — dřívější skládání do
      # UTF-8 Stringu fungovalo jen shodou okolností.
      File.binwrite(path, "žluťoučký kůňÿ" * 500)
      yield path, (PRE.b + File.binread(path) + EPI.b)
    end
  end

  def test_size_matches_the_body
    with_payload do |path, expected|
      assert_equal expected.bytesize, Surfer::MultipartStream.new(PRE, path, EPI).size
    end
  end

  def test_chunked_read_matches
    with_payload do |path, expected|
      s = Surfer::MultipartStream.new(PRE, path, EPI)
      out = +"".b
      while (chunk = s.read(1024))
        out << chunk
      end
      s.close
      assert_equal expected, out
    end
  end

  def test_read_into_outbuf_matches
    with_payload do |path, expected|
      s = Surfer::MultipartStream.new(PRE, path, EPI)
      out = +"".b
      buf = +""
      out << buf while s.read(777, buf)
      s.close
      assert_equal expected, out
    end
  end

  def test_io_copy_stream_matches
    with_payload do |path, expected|
      s = Surfer::MultipartStream.new(PRE, path, EPI)
      sink = StringIO.new(+"".b)
      IO.copy_stream(s, sink)
      s.close
      assert_equal expected, sink.string
    end
  end

  def test_read_returns_nil_at_eof
    with_payload do |path, _|
      s = Surfer::MultipartStream.new(PRE, path, EPI)
      nil while s.read(65_536)
      assert_nil s.read(16)
      s.close
    end
  end
end
