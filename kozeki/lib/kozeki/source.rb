# frozen_string_literal: true
require 'digest/sha2'

require 'kozeki/record'
require 'kozeki/item'

module Kozeki
  # Source represents a source text file.
  class Source
    # @param path [Array<String>]
    def initialize(path:, meta:, mtime:, content:, loader:)
      raise ArgumentError, "path fragment cannot include /" if path.any? { _1.include?('/') }
      @path = path
      @meta = meta
      @mtime = mtime
      @content = content
      @build = nil

      @loader = loader

      raise ArgumentError, "path fragment cannot include /" if path.any? { _1.include?('/') }
      raise ArgumentError, "id cannot include /" if id.include?('/')
    end

    attr_reader :path, :mtime, :content, :loader
    attr_accessor :meta
    attr_accessor :build

    def id
      meta.fetch(:id) do
        "ao_#{Digest::SHA256.hexdigest(path.join('/'))}"
      end.to_s
    end

    def timestamp
      meta[:timestamp]&.then { Time.xmlschema(_1) }
    end

    def collections
      meta[:collections] || []
    end

    # Relative file path of built Item.
    def item_path
      ['items', "#{id}.json"]
    end

    def to_record
      Record.from_source(self)
    end

    def build_item
      data = loader.build(self)
      Item.new(
        id:,
        data:,
        meta:,
        build: @build || {},
      )
    end
  end
end
