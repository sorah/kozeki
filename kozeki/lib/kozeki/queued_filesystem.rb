require 'kozeki/filesystem'
require 'thread'

module Kozeki
  class QueuedFilesystem
    include Kozeki::Filesystem
    Operation = Data.define(:method, :args)

    def initialize(filesystem:, threads: 6)
      @backend = filesystem
      @lock = Mutex.new
      @threads_num = threads
      @threads = nil
      @queue = nil
      start
    end

    def start
      @lock.synchronize do
        queue = @queue = Queue.new
        @threads = @threads_num.times.map { Thread.new(queue, &method(:do_worker)) }
      end
    end

    def flush
      return unless @threads
      ths, q = @lock.synchronize do
        [@threads, @queue]
      end
      start
      q.close
      ths.each(&:value)
    end

    def write(path, string)
      @queue.push Operation.new(method: :write, args: [path, string])
      nil
    end

    def delete(path)
      @queue.push Operation.new(method: :delete, args: [path])
      nil
    end

    private def do_worker(q)
      while op = q.pop
        case op.method
        when :write
          @backend.write(*op.args)
        when :delete
          @backend.delete(*op.args)
        else
          raise "unknown operation #{op.inspect}"
        end
      end
    end

    def read(...) = @backend.read(...)
    def read_with_mtime(...) = @backend.read_with_mtime(...)
    def list(...) = @backend.list(...)
    def list_entries(...) = @backend.list_entries(...)
    def watch(...) = @backend.watch(...)
    def retain_only(...) = @backend.retain_only(...)
  end
end
