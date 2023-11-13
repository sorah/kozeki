# frozen_string_literal: true
require 'kozeki/state'
module Kozeki
  class Client
    # @param config [Config]
    def initialize(config:)
      @config = config
      @state = State.open(config.state_path)
    end
  end
end
