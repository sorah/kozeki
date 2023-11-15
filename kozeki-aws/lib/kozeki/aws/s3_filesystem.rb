# frozen_string_literal: true
require 'aws-sdk-s3'
require 'stringio'
require 'kozeki/filesystem'

module Kozeki
  module Aws
    class S3Filesystem
      include Kozeki::Filesystem

      def initialize(client: ::Aws::S3::Client.new, bucket:, prefix:, delimiter: '/', cache_control: nil)
        @s3 = client
        @bucket = bucket
        @prefix = prefix
        @delimiter = delimiter
        @cache_control = cache_control || method(:default_cache_control)
      end

      attr_reader :s3, :bucket, :prefix, :delimiter

      def read_with_mtime(path)
        r = @s3.get_object(
          bucket:,
          key: make_key(path),
        )
        [
          r.body,
          r.last_modified,
        ]
      rescue Aws::S3::Errors::NotFound
        raise Kozeki::Filesystem::NotFound
      end

      def write(path, string)
        key = make_key(path)
        @s3.put_object(
          bucket:,
          key:,
          body: StringIO.new(string, 'r'),
          content_type: content_type_for(path),
          cache_control: @cache_control[key],
        )
        nil
      end

      def delete(path)
        @s3.delete_object(
          bucket:,
          key: make_key(path),
        )
        nil
      rescue Aws::S3::Errors::NotFound
        nil
      end

      def list_entries
        @s3.list_objects_v2(
          bucket:,
          prefix:,
        ).flat_map do |page|
          page.contents.map do |content|
            Kozeki::Filesystem::Entry.new(
              path: key_to_path(content.key),
              mtime: content.last_modified,
            )
          end
        end
      end

      private def make_key(path)
        "#{prefix}#{path.join(delimiter)}"
      end

      private def key_to_path(key)
        raise "key didn't start with prefix" unless key.start_with?(prefix)
        key[prefix.size..-1].split(delimiter)
      end

      private def content_type_for(path)
        case path[-1]
        when /\.json$/
          'application/json; charset=utf-8'
        else
          'application/octet-stream'
        end
      end

      private def default_cache_control(key)
        nil
      end
    end
  end
end
