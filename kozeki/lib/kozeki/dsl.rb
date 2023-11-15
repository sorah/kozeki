module Kozeki
  class Dsl
    def initialize(options)
      @options = options
    end

    attr_reader :options

    def self.load_file(path, options: {})
      d = self.new(options)
      d.base_directory(File.dirname(path))
      d.instance_eval(File.read(path), path, 1)
      d
    end

    def self.eval(options: {}, &block)
      d = self.new(options)
      d.base_directory('.')
      d.instance_eval(&block)
      d
    end

    def base_directory(path)
      @options[:base_directory] = path
    end

    def source_directory(path)
      @options[:source_directory] = path
    end

    def destination_directory(path)
      @options[:destination_directory] = path
    end

    def cache_directory(path)
      @options[:cache_directory] = path
    end

    def collection_list_included_prefix(*prefixes)
      (@options[:collection_list_included_prefix] ||= []).concat prefixes.flatten.map(&:to_s)
    end

    def collection_options(prefix:, **options)
      @options[:collection_options] ||= []
      # FIXME: recursive dependency :<
      @options[:collection_options].push(Config::CollectionOptions.new(prefix:, **options))
    end

    def hide_collections_in_item(bool)
      @options[:hide_collections_in_item] = bool
    end

    def metadata_decorator(&block)
      raise ArgumentError, "block must be given" unless block
      (@options[:metadata_decorators] ||= []).push(block)
    end

    def source_filesystem(x)
      @options[:source_filesystem] = x
    end

    def destination_filesystem(x)
      @options[:destination_filesystem] = x
    end

    def use_event_time_as_mtime(bool)
      @options[:use_event_time_as_mtime] = bool
    end

    def build_info(&block)
      raise ArgumentError, "block must be given" unless block
      (@options[:build_info_generators] ||= []).push(block)
    end

    def on_after_build(&block)
      (@options[:after_build_callbacks] ||= []).push(block)
    end
  end
end
