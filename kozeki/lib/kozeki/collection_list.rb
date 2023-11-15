# frozen_string_literal: true

module Kozeki
  class CollectionList
    def initialize(names)
      @names = names
    end

    attr_reader :names

    def as_json(build: {})
      {
        kind: 'collection_list',
        collections: names.sort.map do |name|
          {
            name:,
            path: ['collections', "#{name}.json"].join('/'),
          }
        end,
        kozeki_build: build,
      }
    end

    def item_path
      ['collections.json']
    end
  end
end
