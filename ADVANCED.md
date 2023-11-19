# Advanced Usage

Actual usage in https://diary.sorah.jp/ and https://blog.sorah.jp/

```
require 'base64'
require 'logger'
require 'kozeki/aws'
require 'kozeki/queued_filesystem'
require 'aws-sdk-s3'

cache_directory './cache'
source_directory './entries'

case
when ENV['LOCAL']
  destination_directory './build'
else
  # Use kozeki-aws gem for destination. Combine Kozeki::QueuedFilesystem to run upload process in background threads.
  destination_filesystem Kozeki::QueuedFilesystem.new(
    threads: 6,
    filesystem: Kozeki::Aws::S3Filesystem.new(
      client: ::Aws::S3::Client.new(logger: Logger.new($stdout)),
      bucket: ENV.fetch('KOZEKI_S3_BUCKET'),
      prefix: ENV['KOZEKI_S3_PREFIX'] || 'dev/',
    ),
  )
end

# Restrict what to be included in collections.json.
collection_list_included_prefix('archive:month:', 'archive:year:', 'category:')
# Never emit `.meta.collections` in rendered items.
hide_collections_in_item true


# Per-collection customization based on its prefix
collection_options(
  prefix: 'category:',
  # Enable pagination
  paginate: true,
  max_items: 50,
  # Restrict metadata embedded in a collection by its keys
  meta_keys: %i(title slug permalink timestamp site categories unlisted),
)
collection_options(
  prefix: 'permalink:',
  meta_keys: %i(slug permalink site),
)
collection_options(
  prefix: 'site:',
  # When specified `max_items` but without `paginate`, then only latest N items will be included.
  max_items: 20,
  meta_keys: %i(title slug permalink timestamp site categories unlisted),
)

metadata_decorator do |meta, source|
  meta[:timestamp] = meta[:published_at]&.then { Time.iso8601(_1) }
  meta[:timestamp] ||= meta[:created_at]&.then { Time.iso8601(_1) }
  meta[:timestamp] ||= source.mtime
  meta[:timestamp] = meta[:timestamp].xmlschema
end

metadata_decorator do |meta, source|
  meta[:categories] ||= []
  meta[:categories] = meta[:categories].sort if meta[:categories]
  meta[:updated_at] ||= source.mtime.xmlschema
  meta[:modified_at] = source.mtime
end


metadata_decorator do |meta|
  next unless meta[:published_at] && meta[:site]
  next if meta[:unlisted]

  meta[:collections] ||= []
  meta[:collections].push("site:#{meta[:site]}")
  time = Time.xmlschema(meta.fetch(:timestamp))
  #meta[:collections].push(time.strftime("archive:month:#{meta[:site]}:%Y:%m"))
  meta[:collections].push(time.strftime("archive:year:#{meta[:site]}:%Y"))
  meta[:collections].concat (meta[:categories] || []).map { "category:#{meta[:site]}:#{_1}" }
end

metadata_decorator do |meta|
  next if meta[:published_at]
  meta[:collections] ||= []
  meta[:collections].push('draft')
nd

metadata_decorator do |meta|
  meta[:permalink] = "#{Time.xmlschema(meta.fetch(:timestamp)).strftime('%Y/%m/%d')}/#{meta.fetch(:slug)}"
  meta[:collections] ||= []
  meta[:collections].push "permalink:#{meta[:site] || '_site_'}:#{meta[:permalink].tr('/','!')}"
end

# will be rendered into .kozeki_build in an item
build_info do |data|
  data[:ci] = "#{ENV['GITHUB_SERVER_URL']}/#{ENV['GITHUB_REPOSITORY']}/actions/runs/#{ENV['GITHUB_RUN_ID']}" if ENV['GITHUB_RUN_ID']
end
```
