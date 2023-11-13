module Kozeki
  module Filesystem
    Entry = Data.define(:path, :mtime)
    Event = Data.define(:op, :path, :time)

    class NotFound < StandardError; end

    def read(path)
      raise NotImplementedError
    end

    def read_with_mtime(path)
      raise NotImplementedError
    end

    def write(path, string)
      raise NotImplementedError
    end

    def delete(path)
      raise NotImplementedError
    end

    def list
      list_entries.map(&:path)
    end

    def list_entries
      raise NotImplementedError
    end

    def watch
      raise NotImplementedError
    end

    def retain_only(files)
      to_remove = list() - files
      to_remove.each do |path|
        delete(path)
      end
    end
  end
end
