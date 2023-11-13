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

    def metadata_decorator(&block)
      (@options[:metadata_decorators] ||= []).push(block)
    end

    def source_filesystem(x)
      @options[:destination_filesystem] = x
    end

    def destination_filesystem(x)
      @options[:destination_filesystem] = x
    end
  end
end
