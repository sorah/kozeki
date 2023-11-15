# frozen_string_literal: true
require 'time'

module Kozeki
  class Collection
    def initialize(name, records, options: nil)
      raise ArgumentError, "name cannot include /" if name.include?('/')
      @name = name
      @records = records
      @options = options

      @records_sorted = nil
    end

    attr_reader :name, :records, :options

    def inspect
      "#<#{self.class.name}#{self.__id__} name=#{name.inspect} options=#{options.inspect}>"
    end

    def records_sorted
      @records_sorted ||= @records.sort_by do |record|
        record.timestamp&.then { -_1.to_i } || 0
      end
    end

    def total_pages
      @total_pages ||= calculate_total_pages(records.size)
    end

    def pages
      case
      when records.empty?
        []
      when options&.paginate && options&.max_items
        total_pages.times.map do |i|
          Page.new(parent: self, page: i+1)
        end
      else
        [Page.new(parent: self, page: nil)]
      end
    end

    def item_path_for_page(pagenum)
      case pagenum
      when 0
        raise "[bug] page is 1-origin"
      when nil, 1
        ['collections', "#{name}.json"]
      else
        ['collections', "#{name}", "page-#{pagenum}.json"]
      end
    end

    def item_paths_for_missing_pages(item_count_was)
      total_pages_was = calculate_total_pages(item_count_was)
      if (total_pages_was - total_pages) > 0
        (total_pages+1..total_pages_was).map do |pagenum|
          item_path_for_page(pagenum)
        end
      else
        []
      end
    end

    def calculate_total_pages(count)
      if options&.paginate && options&.max_items
        count.divmod(options.max_items).then {|(a,b)| a + (b>0 ? 1 : 0) }
      else
        count > 0 ? 1 : 0
      end
    end

    class Page
      def initialize(parent:, page:)
        @parent = parent
        @page = page

        @total_pages = nil
      end

      def inspect
        "#<#{self.class.name}#{self.__id__} page=#{@page.inspect} parent=#{@parent.inspect}>"
      end

      def name; @parent.name; end
      def options; @parent.options; end
      def total_pages; @parent.total_pages; end

      def records
        case @page
        when nil
          @parent.records_sorted
        when 0
          raise "[bug] page is 1-origin"
        else
          @parent.records_sorted[(@page - 1) * options.max_items, options.max_items]
        end
      end

      private def meta_as_json(record)
        retval = options&.meta_keys ? record.meta.slice(*options.meta_keys) : record.meta.dup
        retval.delete(:collections) if options&.hide_collections
        retval
      end

      def as_json
        {
          kind: 'collection',
          name: name,
          items: records.map do |record|
            {
              id: record.id,
              path: ['items', "#{record.id}.json"].join('/'),
              meta: meta_as_json(record),
            }
          end.then do |page|
            options&.max_items ? page[0, options.max_items] : page
          end,
        }.tap do |j|
          j[:page] = page_info if @page
        end
      end

      def item_path
        @parent.item_path_for_page(@page)
      end

      def page_info
        return nil unless @page
        prev_page = 1 < @page ? @parent.item_path_for_page(@page-1) : nil
        next_page = @page < total_pages ? @parent.item_path_for_page(@page+1) : nil
        i = {
          self: @page,
          total_pages:,
          first: @parent.item_path_for_page(1).join('/'),
          last: @parent.item_path_for_page(total_pages).join('/'),
          prev: prev_page&.join('/'),
          next: next_page&.join('/'),
        }
        if @page == 1
          i[:pages] = (1..total_pages).map do |pagenum|
            @parent.item_path_for_page(pagenum).join('/')
          end
        end
        i
      end
    end
  end
end
