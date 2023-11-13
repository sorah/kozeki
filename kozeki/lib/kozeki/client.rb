# frozen_string_literal: true
require 'kozeki/state'
require 'kozeki/build'

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
          loader: @config.loader,
          incremental_build:,
          events:,
          logger: @config.logger,
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
      end
      sleep
    ensure
      stop&.call
    end
  end
end
