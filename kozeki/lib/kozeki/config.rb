# frozen_string_literal: true
require 'kozeki/dsl'
require 'kozeki/loader_chain'
require 'kozeki/local_filesystem'
require 'kozeki/markdown_loader'
require 'logger'

module Kozeki
  class Config
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

    def metadata_decorators
      @options.fetch(:metadata_decorators, [])
    end

    def state_path
      cache_directory ? File.join(cache_directory, 'state.sqlite3') : ':memory:'
    end

    def source_filesystem
      @source_filesystem ||= @options.fetch(:source_filesystem, LocalFilesystem.new(File.expand_path(source_directory, base_directory)))
    end

    def destination_filesystem
      @destination_filesystem ||= @options.fetch(:destination_filesystem, LocalFilesystem.new(File.expand_path(destination_directory, base_directory)))
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
