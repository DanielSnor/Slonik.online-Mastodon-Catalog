# frozen_string_literal: true

# lib/catalog.rb — katalog má dvě podoby a tohle je jediné místo, které ví, jak
# se jedna převádí na druhou.
#
#   ÚLOŽIŠTĚ (data/catalog.json)  plné záznamy pro pipeline
#   PUBLIKOVANÉ (web/data.json)   jen pole, která frontend vykresluje
#
# Sdílí to `update_catalog.rb` (píše obojí po každém checkpointu) a
# `cache_avatars.rb` (dopíše lokální avatary a publikuje znovu).

require "json"
require_relative "paths"

module Catalog
  # Pole, která jdou na web. Cokoli mimo tenhle seznam zůstává jen v úložišti —
  # interní klíče (mastodon_id, stav ověření) i _ai_description, což jsou strojově
  # psané charakteristiky konkrétních lidí, které web nikde nezobrazuje.
  #
  # Nové pole, které má frontend zobrazovat, se sem MUSÍ doplnit.
  PUBLIC_KEYS = %w[
    id display_name type family language categories avatar avatar_local bio
    followers posts_week created_at last_status_at profile_url source_platforms
    bot followers_delta activity_delta
  ].freeze

  module_function

  # Atomický zápis (temp + rename) — crash nezanechá rozbitý JSON.
  def write_json(path, data, pretty: true)
    tmp = "#{path}.tmp"
    File.write(tmp, pretty ? JSON.pretty_generate(data) : JSON.generate(data))
    File.rename(tmp, path)
  end

  def slim(records)
    records.map { |rec| rec.select { |k, _| PUBLIC_KEYS.include?(k) } }
  end

  # Publikovaná verze: jen veřejná pole, kompaktní JSON (pretty print přidá
  # stovky kB, které si stáhne každý návštěvník).
  def publish(records, path)
    write_json(path, slim(records), pretty: false)
  end

  def load(path)
    parsed = JSON.parse(File.read(path, encoding: "UTF-8"))
    parsed.is_a?(Array) ? parsed : []
  end
end
