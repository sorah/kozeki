# frozen_string_literal: true
require 'kozeki/dsl'
require 'kozeki/loader_chain'
require 'kozeki/local_filesystem'
require 'kozeki/markdown_loader'
require 'logger'

module Kozeki
  class Config
    CollectionOptions = Struct.new(:prefix, :max_items, :paginate, :meta_keys, :hide_collections)

    def initialize(options)
      @options = options
      @source_filesystem = nil
      @destination_filesystem = nil
      @loader = nil
      @logger = nil
    end

    def self.load_file(path)
      new(Dsl.load_file(path).options)
    end

    def self.configure(&block)
      new(Dsl.eval(&block).options)
    end

    def [](k)
      @options[k]
    end

    def fetch(k,*args)
      @options.fetch(k,*args)
    end

    def base_directory
      @options.fetch(:base_directory, '.')
    end

    def source_directory
      @options.fetch(:source_directory)
    end

    def destination_directory
      @options.fetch(:destination_directory)
    end

    def cache_directory
      @options.fetch(:cache_directory, nil)
    end

    def collection_list_included_prefix
      @options.fetch(:collection_list_included_prefix, nil)
    end

    def collection_options
      @options.fetch(:collection_options, [])
    end

    def hide_collections_in_item
      @options.fetch(:hide_collections_in_item, false)
    end

    def metadata_decorators
      @options.fetch(:metadata_decorators, [])
    end

    def after_build_callbacks
      @options.fetch(:after_build_callbacks, [])
    end

    def state_path
      cache_directory ? File.join(File.expand_path(cache_directory, base_directory), 'state.sqlite3') : ':memory:'
    end

    def source_filesystem
      @source_filesystem ||= @options.fetch(:source_filesystem) { LocalFilesystem.new(File.expand_path(source_directory, base_directory)) }
    end

    def destination_filesystem
      @destination_filesystem ||= @options.fetch(:destination_filesystem) { LocalFilesystem.new(File.expand_path(destination_directory, base_directory)) }
    end

    def use_event_time_as_mtime
      @options.fetch(:use_event_time_as_mtime, false)
    end

    def build_info_generators
      @options.fetch(:build_info_generators, [])
    end

    def loader
      @loader ||= LoaderChain.new(
        loaders: [MarkdownLoader],
        decorators: metadata_decorators,
      )
    end

    def logger
      @logger ||= Logger.new($stdout)
    end
  end
end
