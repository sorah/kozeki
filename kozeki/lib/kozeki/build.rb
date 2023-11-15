# frozen_string_literal: true
require 'json'
require 'kozeki/config'
require 'kozeki/state'
require 'kozeki/item'
require 'kozeki/collection'
require 'kozeki/collection_list'

module Kozeki
  class Build

    # @param state [State]
    def initialize(state:, source_filesystem:, destination_filesystem:, collection_list_included_prefix: nil, hide_collections_in_item: false, collection_options: [], use_event_time_as_mtime: false, loader:, events: nil, incremental_build:, build_data: nil, logger: nil)
      @state = state

      @source_filesystem = source_filesystem
      @destination_filesystem = destination_filesystem
      @collection_list_included_prefix = collection_list_included_prefix
      @collection_options = collection_options
      @hide_collections_in_item = hide_collections_in_item
      @use_event_time_as_mtime = use_event_time_as_mtime
      @loader = loader
      @loader_cache = {}
      @logger = logger

      @events = events
      @incremental_build = incremental_build

      @build_data = build_data

      @updated_files = []
      @deleted_files = []
      @build_id = nil
    end

    attr_accessor :events, :incremental_build
    attr_reader :updated_files, :deleted_files, :build_data

    def inspect
      "#<#{self.class.name}#{self.__id__}>"
    end

    def build_data
      @build_data || {}
    end

    def incremental_build_possible?
      @state.build_exist?
    end

    def incremental_build?
      incremental_build_possible? && @incremental_build
    end

    def full_build?
      !incremental_build?
    end

    def perform
      raise "can't reuse" if @build_id
      if full_build?
        @logger&.info "Starting full build"
      else
        @logger&.info "Starting incremental build"
      end

      @state.transaction do
        process_prepare
        process_events
      end
      @state.transaction do
        process_items_remove
        process_items_update
        @destination_filesystem.flush
      end
      @state.transaction do
        process_garbage
        @destination_filesystem.flush
      end
      @state.transaction do
        process_collections
        @destination_filesystem.flush
      end
      @state.transaction do
        process_commit
        @destination_filesystem.flush
      end
    end

    private def process_prepare
      @logger&.debug "=== Prepare ==="
      @state.clear! if full_build?
      @build_id = @state.create_build
      @logger&.debug "Build ID: #{@build_id.inspect}"
      @build_data = {build: {id: @build_id.to_s, state: @state.finger}}.merge(@build_data) if @build_data
    end

    private def process_events
      @logger&.debug "=== Process incoming events ==="
      events = if full_build? || @events.nil?
        fs_list = @source_filesystem.list_entries()
        fs_list.map do |entry|
          Filesystem::Event.new(op: :update, path: entry.path, time: full_build? ? nil : entry.mtime.floor(4))
        end
      else
        @events.dup
      end

      if fs_list
        seen_paths = {}
        events.each do |event|
          next unless event.op == :update
          seen_paths[event.path] = true
        end
        @state.list_record_paths.reject do |path|
          seen_paths[path]
        end.each do |path|
          events.push(Filesystem::Event.new(op: :delete, path:, time: nil))
        end
      end

      events.each do |event|
        @logger&.debug "> #{event.inspect}" if incremental_build? && @events
        case event.op
        when :update
          if event.time
            begin
              record = @state.find_record_by_path!(event.path)
              diff = event.time.to_f.floor(3) - record.mtime.to_f.floor(3)
              if diff > 0.005
                @logger&.debug "> #{event.inspect}"
                @logger&.debug "  #{record.mtime} (#{record.mtime.to_f.floor(3)}) < #{event.time} (#{event.time.to_f.floor(3)})"
              else
                next
              end
            rescue State::NotFound
            end
          end

          source = load_source(event.path, mtime: event.time)
          record = @state.save_record(source.to_record)
          @state.set_record_pending_build_action(record, :update)
          @logger&.info "ID change: #{event.path.inspect}; #{record.id_was.inspect} => #{record.id.inspect}" if record.id_was
        when :delete
          begin
            record = @state.find_record_by_path!(event.path)
            @state.set_record_pending_build_action(record, :remove)
          rescue State::NotFound
          end
        else
          raise "unknown op #{event.inspect}"
        end
      end
    end

    private def process_items_remove
      @logger&.debug "=== Delete items for removed sources ==="
      removed_records = @state.list_records_by_pending_build_action(:remove)
      removed_records.each do |record|
        if @state.list_records_by_id(record.id).any? { _1.pending_build_action == :update }
          @logger&.warn "Skip deletion: #{record.id.inspect} (#{record.path.inspect})"
          next
        end
        @logger&.info "Delete: #{record.id.inspect} (#{record.path.inspect})"
        filesystem_delete(['items', "#{record.id}.json"])
        @state.set_record_collections_pending(record.id, [])
      end
    end

    private def process_items_update
      @logger&.debug "=== Render items for updated sources ==="
      updating_records = @state.list_records_by_pending_build_action(:update)
      updating_records.each do |record|
        @logger&.info "Render: #{record.id.inspect} (#{record.path.inspect})"
        source = load_source(record.path)

        # ID uniqueness check
        _existing_record = begin
          @state.find_record!(source.id)
        rescue State::NotFound; nil
        end

        item = build_item(source)
        json = item.as_json(
          hide_collections_in_item: @hide_collections_in_item,
        )
        filesystem_write(source.item_path, "#{JSON.generate(json)}\n")
        @state.set_record_collections_pending(item.id, item.meta.fetch(:collections, []))
      end
    end

    private def process_garbage
      @logger&.debug "=== Collect garbages; items without source ==="
      item_ids = @state.list_item_ids_for_garbage_collection
      item_ids.each do |item_id|
        @logger&.debug "Checking: #{item_id.inspect}"
        records = @state.list_records_by_id(item_id)
        if records.empty?
          @logger&.info "Garbage: #{item_id.inspect}"
          @state.mark_item_id_to_remove(item_id)
          @state.set_record_collections_pending(item_id, [])
          filesystem_delete(['items', "#{item_id}.json"])
        end
      end
    end

    private def process_collections
      @logger&.debug "=== Render updated collections ==="
      collections = @state.list_collection_names_pending
      return if collections.empty?

      collections.each do |collection_name|
        records = @state.list_collection_records(collection_name)
        record_count_was = @state.count_collection_records(collection_name)

        collection = make_collection(collection_name, records)
        collection.pages.each do |page|
          @logger&.info "Render: Collection #{collection_name.inspect} (#{page.item_path.inspect})"
          filesystem_write(page.item_path, "#{JSON.generate(page.as_json)}\n")
        end
        collection.item_paths_for_missing_pages(record_count_was).each do |path|
          @logger&.info "Delete: Collection #{collection.inspect} (#{path.inspect})"
          filesystem_delete(path)
        end
      end

      @logger&.info "Render: CollectionList"
      collection_names = @state.list_collection_names_with_prefix(*@collection_list_included_prefix)
      collection_list = CollectionList.new(collection_names)
      filesystem_write(collection_list.item_path, "#{JSON.generate(collection_list.as_json(build: build_data))}\n")
    end

    private def process_commit
      @logger&.debug "=== Finishing build ==="
      @logger&.debug "Flush pending actions"
      @state.process_markers!
      if full_build?
        @logger&.info "Delete: untouched files from destination"
        @destination_filesystem.retain_only(@updated_files)
      end
      @logger&.debug "Mark build completed"
      @state.mark_build_completed(@build_id)
      # TODO: @state.remove_old_builds
    end

    private def load_source(path, mtime: nil)
      @loader_cache[path] ||= begin
        @logger&.debug("Load: #{path.inspect}")
        val = @loader.try_read(path: path, filesystem: @source_filesystem) or raise "can't read #{path.inspect}"
        val.build = build_data
        val.mtime = mtime if mtime && @use_event_time_as_mtime
        val
      end
    end

    private def build_item(source)
      source.build_item
    end

    private def make_collection(name, records)
      Collection.new(name, records, options: collection_option_for(name))
    end

    private def collection_option_for(collection_name)
      retval = nil
      len = -1
      @collection_options.each do |x|
        if collection_name.start_with?(x.prefix) && x.prefix.size > len
          retval = x
          len = x.prefix.size
        end
      end
      retval = retval&.dup || Config::CollectionOptions.new
      retval.hide_collections = true if @hide_collections_in_item && retval.hide_collections.nil?
      retval
    end

    private def filesystem_write(path, body)
      @destination_filesystem.write(path, body)
      @updated_files << path
      nil
    end

    private def filesystem_delete(path)
      @destination_filesystem.delete(path)
      @deleted_files << path
      nil
    end
  end
end
