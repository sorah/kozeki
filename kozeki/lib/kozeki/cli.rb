# frozen_string_literal: true
require 'thor'

require 'kozeki/client'
require 'kozeki/config'

module Kozeki
  class Cli < Thor
    package_name 'kozeki'

    desc 'build CONFIG_FILE', 'run a one-off build using CONFIG_FILE'
    method_options :full => :boolean
    def build(config_file)
      client = make_client(config_file)
      client.build(
        incremental_build: !options[:full],
        events: nil,
      )
    end

    desc 'watch CONFIG_FILE', 'run a continuous build by watching source filesystem using CONFIG_FILE'
    def watch(config_file)
      client = make_client(config_file)
      client.watch
    end

    desc 'debug-state CONFIG_FILE', ''
    def debug_state(config_file)
      client = make_client(config_file)
      state = State.open(path: client.config.state_path)
      state.db.execute(%{select * from "records" order by "id" asc}).map { p record: _1 }
      state.db.execute(%{select * from "collection_memberships" order by "collection" asc, "record_id" asc}).map { p collection_membership: _1 }
      state.db.execute(%{select * from "item_ids" order by "id" asc}).map { p item_id: _1 }
    end

    no_commands do
      private def make_client(config_file)
        config = Config.load_file(config_file)
        Client.new(config:)
      end
    end
  end
end
