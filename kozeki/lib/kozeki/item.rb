require 'time'

module Kozeki
  # Item represents a built item from Source.
  class Item
    class ParseError < StandardError; end

    def self.load_from_json(json_string)
      j = JSON.parse(json_string, symbolize_names: true)
      raise ParseError, ".kind must be `item`" unless j[:kind] == 'item'
      id = j.fetch(:id)
      data = j.fetch(:data)
      meta = j.fetch(:meta, {})
      build = j.fetch(:kozeki_build, {})
      Item.new(id:, data:, meta:, build:)
    end

    def initialize(id:, data:, meta: nil, build: nil)
      @id = id
      @data = data
      @meta = meta
      @build = build
    end

    attr_reader :id, :data, :meta, :build

    def id
      meta.fetch(:id)
    end

    def as_json
      {
        kind: 'item',
        id: id,
        meta: meta.transform_values do |v|
          case v
          when Time
            v.xmlschema
          else
            v
          end
        end,
        data:,
        kozeki_build: build,
      }
    end
  end
end
