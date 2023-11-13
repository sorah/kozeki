# frozen_string_literal: true
require 'yaml'
require 'commonmarker'
require 'kozeki/source'

module Kozeki
  module MarkdownLoader
    def self.try_read(path:, filesystem:)
      basename = path.last
      return nil unless basename.end_with?('.md') || basename.end_with?('.mkd') || basename.end_with?('.markdown')
      content, mtime = filesystem.read_with_mtime(path)
      m = content.match(/\A\s*^---$(.+?)^---$/m)
      meta = if m
        YAML.safe_load(m[1], symbolize_names: true)
      else
        {}
      end
      Source.new(
        path:,
        meta:,
        mtime:,
        content:,
        loader: self,
      )
    end

    def self.build(source)
      html = Commonmarker.to_html(source.content, options: {
        render: {
          unsafe: true,
        },
        extension: {
          strikethrough: true,
          tagfilter: false,
          table: true,
          autolink: true,
          tasklist: true,
          superscript: true,
          header_ids: "#{source.id}--",
          footnotes: true,
          description_lists: true,
          front_matter_delimiter: '---',
          shortcodes: true,
        },
      })

      {
        html: html,
      }
    end
  end
end
