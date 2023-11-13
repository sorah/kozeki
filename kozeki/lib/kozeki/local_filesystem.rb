# frozen_string_literal: true
require 'kozeki/filesystem'
require 'fileutils'

module Kozeki
  class LocalFilesystem
    include Filesystem

    def initialize(base_directory)
      @base = base_directory
    end

    # @param path [Array]
    def read(path)
      File.read(File.join(@base, *path))
    rescue Errno::ENOENT
      raise Filesystem::NotFound
    end

    # @param path [Array]
    def read_with_mtime(path)
      [
        read(path),
        File.mtime(File.join(@base, *path)),
      ]
    end

    # @param path [Array]
    def write(path, string)
      path = File.join(@base, *path)
      dirname = File.dirname(path)
      FileUtils.mkdir_p(dirname)
      File.write(path, string)
    end

    # @param path [Array]
    def delete(path)
      File.unlink(File.join(@base, *path))
    rescue Errno::ENOENT
    end

    def list_entries
      range = File.join(@base, 'x')[0..-2].size .. -1
      Dir[File.join(@base, '**', '*')].filter_map do |fspath|
        path =  fspath[range].split(File::SEPARATOR)
        next if File.directory?(fspath) rescue nil
        Filesystem::Entry.new(
          path:,
          mtime: File.mtime(fspath),
        )
      end
    end

    def flush
      # do nothing
    end
  end
end
