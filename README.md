# Kozeki: Convert markdown files to rendered JSON files with index for static website blogging

1. Collect markdown files with front matter (for metadata)
2. Decorate metadata using Ruby scripts
3. Render as HTML in JSON files, with final metadata
4. Emit index JSON files for listing articles in various ways
5. Use JSON files to run your website, e.g. with Nextjs

## Installation

```ruby
# Gemfile
gem 'kozeki'
```

## Configuration

```ruby
source_directory './articles'
destination_directory './build'
cache_directory './cache'

metadata_decorator do |meta|
  next unless meta[:published_at]
  meta[:timestamp] = Time.iso8601(meta[:published_at])

  meta[:collections] ||= []
  meta[:collections].push('index')
  meta[:collections].push(meta.fetch(:timestamp).strftime('archive:%Y:%m'))
  meta[:collections].concat (meta[:categories] || []).map { "category:#{_1}" }
end

metadata_decorator do |meta|
  next if meta[:published_at]
  meta[:collections] ||= []
  meta[:collections].push('draft')
end

metadata_decorator do |meta, source|
  meta[:updated_at] = File.mtime(source.path)
end

metadata_decorator do |meta|
  meta[:permalink] = "/#{meta.fetch(:timestamp).strftime('%Y/%m/%d')}/#{meta.fetch(:slug)}"
end
```

## Run

Example input at `./articles/2023/foo.md`:

```markdown
---
title: foo bar
published_at: 2023-08-06T17:50:00+09:00
categories: [diary]
slug: foo-bar
---

## foo bar

blah blah
```

Example output:

```jsonc
// out/items/ca1c4d8da0e7823fa8b31fb4f15a727d9a11c57ca0736b7c6a40bd3906ca85f1.json
{
  "kind": "item",
  "path": "items/ca1c4d8da0e7823fa8b31fb4f15a727d9a11c57ca0736b7c6a40bd3906ca85f1.json",
  "meta": {
    "id": "ca1c4d8da0e7823fa8b31fb4f15a727d9a11c57ca0736b7c6a40bd3906ca85f1",
    "title": "foo bar",
    "collections": ["archive:2023:08", "category:diary"],
    "timestamp": "2023-08-06T17:50:00+09:00",
    "published_at": "2023-08-06T17:50:00+09:00",
    "updated_at": "2023-08-06T18:00:00+09:00"
  },
  "data": {
    "html": "<h2>foo bar</h2><p>blah blah</p>"
  },
  "kozeki_build": {
    "built_at": ""
  }
}
```

```jsonc
// out/collections/archive:2023:08.json
{
  "kind": "collection",
  "name": "archive:2023:08",
  "items": [
    {
      "path": "items/ca1c4d8da0e7823fa8b31fb4f15a727d9a11c57ca0736b7c6a40bd3906ca85f1.json",
      "meta": {
        "id": "ca1c4d8da0e7823fa8b31fb4f15a727d9a11c57ca0736b7c6a40bd3906ca85f1",
        "title": "foo bar",
        "collections": ["archive:2023:08", "category:diary"],
        "timestamp": "2023-08-06T17:50:00+09:00",
        "published_at": "2023-08-06T17:50:00+09:00",
        "updated_at": "2023-08-06T18:00:00+09:00"
      }
    }
  ]
}
```

## Usage

```
bundle exec kozeki build ./config.rb
```

### Known metadata keys

- `id` (string): Static identifier for a single markdown file. Used for final JSON file output. Default to file path.
- `collections` (string[]): Specify index files to include a file
- `timestamp` (Time or RFC3339 String): Timestamp for file

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
