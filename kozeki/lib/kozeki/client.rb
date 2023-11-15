# frozen_string_literal: true
require 'kozeki/state'
require 'kozeki/build'
require 'kozeki/version'

module Kozeki
  class Client
    # @param config [Config]
    def initialize(config:)
      @config = config
    end

    attr_reader :config

    def build(incremental_build: true, events: nil)
      begin
        state = State.open(path: config.state_path)
        build = Build.new(
          state: state,
          source_filesystem: @config.source_filesystem,
          destination_filesystem: @config.destination_filesystem,
          collection_list_included_prefix: @config.collection_list_included_prefix,
          collection_options: @config.collection_options,
          hide_collections_in_item: @config.hide_collections_in_item,
          loader: @config.loader,
          incremental_build:,
          events:,
          logger: @config.logger,
          build_data: generate_build_data,
        )
        build.perform
      ensure
        state&.close
      end

      @config.after_build_callbacks.each do |cb|
        cb.call(build)
      end
    end

    def watch
      build(incremental_build: true, events: nil)
      stop = @config.source_filesystem.watch do |events|
        build(incremental_build: true, events: events)
        $stdout.flush rescue nil
      end
      sleep
    ensure
      stop&.call
    end

    private def generate_build_data
      data = {
        version: Kozeki::VERSION.to_s,
      }
      @config.build_info_generators.each do |cb|
        cb.call(data)
      end
      data
    end
  end
end
