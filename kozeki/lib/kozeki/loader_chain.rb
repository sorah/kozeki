module Kozeki
  class LoaderChain
    def initialize(loaders:, decorators:)
      @loaders = loaders
      @decorators = decorators
    end

    def self.try_read(...)
      @loaders.each do |loader|
        source = loader.try_read(...)
        next unless source
        @decorators.each do |decorator|
          decorator.call(source.meta, source)
        end
        return source
      end
      nil
    end
  end
end
