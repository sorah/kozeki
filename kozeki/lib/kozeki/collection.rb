# frozen_string_literal: true
require 'time'

module Kozeki
  class Collection
    def initialize(name, records, options: nil)
      raise ArgumentError, "name cannot include /" if name.include?('/')
      @name = name
      @records = records
      @options = options
    end

    attr_reader :name, :records, :options

    def as_json
      {
        kind: 'collection',
        name: name,
        items: records.sort_by do |record|
          record.timestamp&.then { -_1.to_i } || 0
        end.map do |record|
          {
            id: record.id,
            path: ['items', "#{record.id}.json"].join('/'),
            meta: options&.meta_keys ? record.meta.slice(*options.meta_keys) : record.meta,
          }
        end.then do |page|
          options&.max_items ? page[0, options.max_items] : page
        end,
      }
    end

    def item_path
      ['collections', "#{name}.json"]
    end
  end
end
