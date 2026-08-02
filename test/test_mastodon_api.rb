# frozen_string_literal: true

require_relative "helper"
require_relative "../lib/mastodon_api"

# Textové utility a stránkování — čistá logika sdílená všemi skripty.
class TestMastodonAPI < Minitest::Test
  def test_strip_html_keeps_paragraph_breaks_but_not_inline_gaps
    html = "<p>První odstavec.</p><p>Druhý <span class=\"h-card\">@<span>kdosi</span></span> odstavec.</p>"
    assert_equal "První odstavec.\n\nDruhý @kdosi odstavec.", MastodonAPI.strip_html(html)
  end

  def test_strip_html_decodes_entities
    assert_equal "a & b < c > d \"e\" 'f' g",
                 MastodonAPI.strip_html("a &amp; b &lt; c &gt; d &quot;e&quot; &#39;f&#39;&nbsp;g")
  end

  def test_strip_html_handles_nil_and_br
    assert_equal "", MastodonAPI.strip_html(nil)
    assert_equal "a\nb", MastodonAPI.strip_html("a<br>b")
  end

  def test_dominant_language_picks_the_most_frequent
    statuses = [{ "language" => "cs" }, { "language" => "cs" }, { "language" => "en" }]
    assert_equal "cs", MastodonAPI.dominant_language(statuses)
  end

  def test_dominant_language_ignores_missing_values
    assert_nil MastodonAPI.dominant_language([{ "language" => nil }, { "language" => "" }, {}])
    assert_nil MastodonAPI.dominant_language([])
  end

  def test_next_max_id_reads_the_link_header
    link = '<https://x.cz/api/v1/accounts/1/statuses?max_id=123>; rel="next", ' \
           '<https://x.cz/api/v1/accounts/1/statuses?min_id=456>; rel="prev"'
    assert_equal "123", MastodonAPI.next_max_id(link)
    assert_nil MastodonAPI.next_max_id(nil)
    assert_nil MastodonAPI.next_max_id('<https://x.cz/…>; rel="prev"')
  end

  def test_bridges_are_recognized
    assert MastodonAPI.bridge?("bsky.brid.gy")
    assert MastodonAPI.bridge?("neco.brid.gy")
    assert MastodonAPI.bridge?("FLIPBOARD.COM")
    refute MastodonAPI.bridge?("mastodonczech.cz")
  end

  # Rozestup se počítá per host: dotaz na jinou instanci nemá čekat na cizí
  # prodlevu. Testujeme přes stopky, ne přes síť — throttle je privátní, takže
  # ho voláme přes send (chceme ověřit chování, ne rozhraní).
  def test_throttle_waits_only_for_the_same_host
    api = MastodonAPI.new(delay: 0.2)
    t0 = Time.now
    api.send(:throttle, "a.cz")
    api.send(:throttle, "b.cz")
    api.send(:throttle, "c.cz")
    different = Time.now - t0

    t1 = Time.now
    api.send(:throttle, "a.cz")
    same = Time.now - t1

    assert_operator different, :<, 0.1, "různé hosty nemají na sebe čekat"
    assert_operator same, :>, 0.05, "opakovaný dotaz na týž host musí počkat"
  end
end
