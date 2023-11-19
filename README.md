# Kozeki: Markdown to JSON renderer for blogging with static site generator

Backend renderer used at https://diary.sorah.jp/ and https://blog.sorah.jp/

1. Collect markdown files with front matter (for metadata)
2. Decorate metadata using Ruby scripts
3. Render as HTML in JSON files, with final metadata
4. Emit index JSON files for listing articles in various ways
5. Use JSON files to run your website, e.g. with Nextjs

## Concept

- All files in source_directory are imported as _source_
- All sources will be compiled into _item._ Each item represents itself in destination_directory as a single JSON file.
- An item may belong to _collections._
  - Using a _collection_ is only way to generate a list of _items._ You may use a collection just only for a single _item._, such like to implement a index of permalink-to-item.
- Each _collections_ generate JSON files (multiple if paginated) in destination_directory to provide list of _items._

## Installation

Requires Ruby 3.2+

```ruby
# Gemfile
gem 'kozeki'
```

```
bundle install
```

## Example Workflow

### Configuration

```ruby
# config.rb
source_directory './articles'
destination_directory './build'
cache_directory './cache' # to store incremental build state and cache

# Ensure timestamp for all items
metadata_decorator do |meta, source|
  meta[:timestamp] ||= meta[:published_at]
  meta[:timestamp] ||= meta[:created_at]
  meta[:timestamp] ||= source.mtime
end

# Include published items to collections
metadata_decorator do |meta|
  next unless meta[:published_at]

  meta[:collections] ||= []
  meta[:collections].push('index')
  meta[:collections].push(meta.fetch(:timestamp).strftime('archive:%Y:%m'))
  meta[:collections].concat (meta[:categories] || []).map { "category:#{_1}" }
end

# Generate permalink and make a index as a collection
metadata_decorator do |meta|
  meta[:permalink] = "#{meta.fetch(:timestamp).strftime('%Y/%m/%d')}/#{meta.fetch(:slug)}"
  meta[:collections] ||= []
  meta[:collections].push "permalink:#{meta[:permalink].tr('/','!')}"
end
```

Advanced configuration example available at [./ADVANCED.md](./ADVANCED.md)

### Prepare input

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


### Run Build

```
bundle exec kozeki build ./config.rb
```

### Confirm output


Example output:

```jsonc
// out/items/ao_ca1c4d8da0e7823fa8b31fb4f15a727d9a11c57ca0736b7c6a40bd3906ca85f1.json
{
  "kind": "item",
  "id": "ao_ca1c4d8da0e7823fa8b31fb4f15a727d9a11c57ca0736b7c6a40bd3906ca85f1"
  "meta": {
    "id": "ao_ca1c4d8da0e7823fa8b31fb4f15a727d9a11c57ca0736b7c6a40bd3906ca85f1",
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
      "path": "items/ao_ca1c4d8da0e7823fa8b31fb4f15a727d9a11c57ca0736b7c6a40bd3906ca85f1.json",
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

```jsonc
// out/collections.json
{
  "kind": "collection_list",
  "collections": [
    {"id": "archive:2023:08", "path": "collections/archive:2023:08.json"},
    {"id": "category:diary", "path": "collections/category:diary.json"}
  ]
}
```

## Known metadata keys

- `id` (string): Static identifier for a single markdown file. Used for final JSON file output. Default to file path.
- `collections` (string[]): Specify index files to include a file
- `timestamp` (Time or RFC3339 String): Timestamp for file. Used for descending sort of list of items in collection.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
