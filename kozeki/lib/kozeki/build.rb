# frozen_string_literal: true
require 'json'
require 'kozeki/state'
require 'kozeki/item'
require 'kozeki/collection'
require 'kozeki/collection_list'

module Kozeki
  class Build

    # @param state [State]
    def initialize(state:, source_filesystem:, destination_filesystem:, collection_list_included_prefix: nil, collection_options: [], loader:, events: nil, incremental_build:, logger: nil)
      @state = state

      @source_filesystem = source_filesystem
      @destination_filesystem = destination_filesystem
      @collection_list_included_prefix = collection_list_included_prefix
      @collection_options = collection_options
      @loader = loader
      @loader_cache = {}
      @logger = logger

      @events = events
      @incremental_build = incremental_build

      @updated_files = []
      @build_id = nil
    end

    attr_accessor :events, :incremental_build
    attr_reader :updated_files

    def inspect
      "#<#{self.class.name}#{self.__id__}>"
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
      end
      @state.transaction do
        process_garbage
      end
      @state.transaction do
        process_collections
      end
      @state.transaction do
        process_commit
      end
    end

    private def process_prepare
      @logger&.debug "=== Prepare ==="
      @state.clear! if full_build?
      @build_id = @state.create_build
      @logger&.debug "Build ID: #{@build_id.inspect}"
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
        @logger&.debug "> #{event.inspect}" if incremental_build?
        case event.op
        when :update
          if event.time
            begin
              record = @state.find_record_by_path!(event.path)
              next if event.time.to_f.floor(3) <= record.mtime.to_f.floor(3)
            rescue State::NotFound
            end
          end

          source = load_source(event.path)
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
        @destination_filesystem.delete(['items', "#{record.id}.json"])
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
        @destination_filesystem.write(source.item_path, "#{JSON.generate(item.as_json)}\n")
        @state.set_record_collections_pending(item.id, item.meta.fetch(:collections, []))
        @updated_files << source.item_path
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
          @destination_filesystem.delete(['items', "#{item_id}.json"])
        end
      end
    end

    private def process_collections
      @logger&.debug "=== Render updated collections ==="
      collections = @state.list_collection_names_pending
      return if collections.empty?
      collections.each do |collection|
        records = @state.list_collection_records(collection)
        if records.empty?
          @logger&.info "Delete: Collection #{collection.inspect}"
          @destination_filesystem.delete(['collections', "#{collection}.json"])
        else
          @logger&.info "Render: Collection #{collection.inspect}"
          collection = make_collection(collection, records)
          @destination_filesystem.write(collection.item_path, "#{JSON.generate(collection.as_json)}\n")
          @updated_files << collection.item_path
        end
      end

      @logger&.info "Render: CollectionList"
      collection_names = @state.list_collection_names_with_prefix(*@collection_list_included_prefix)
      collection_list = CollectionList.new(collection_names)
      @destination_filesystem.write(collection_list.item_path, "#{JSON.generate(collection_list.as_json)}\n")
      @updated_files << collection_list.item_path
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

    private def load_source(path)
      @loader_cache[path] ||= begin
        @logger&.debug("Load: #{path.inspect}")
        @loader.try_read(path: path, filesystem: @source_filesystem) or raise "can't read #{path.inspect}"
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
      retval
    end
  end
end
