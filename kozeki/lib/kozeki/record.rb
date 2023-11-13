# frozen_string_literal: true

module Kozeki
  # Represents cached metadata of Item and Source in a State
  Record = Data.define(:id, :path, :timestamp, :mtime, :meta, :build, :pending_build_action, :id_was) do
    def self.from_source(s)
      new(
        path: s.path,
        id: s.id,
        timestamp: s.timestamp,
        mtime: s.mtime,
        meta: s.meta,
        build: nil,
        pending_build_action: nil,
        id_was: nil,
      )
    end

    def self.from_row(h)
      new(
        path: h.fetch('path').split('/'),
        id: h.fetch('id'),
        timestamp: Time.at(h.fetch('timestamp')),
        mtime: Time.at(h.fetch('mtime')/1000.0),
        meta: JSON.parse(h.fetch('meta'), symbolize_names: true),
        build: h['build']&.then { JSON.parse(_1, symbolize_names: true) },
        pending_build_action: h.fetch('pending_build_action', 'none')&.to_sym&.then { _1 == :none ? nil : _1 },
        id_was: h.fetch('id_was', nil),
      )
    end

    def path_row
      path.join('/')
    end

    def to_row
      {
        path: path_row,
        id:,
        timestamp: timestamp.to_i,
        mtime: (mtime.floor(4).to_f * 1000).truncate,
        meta: JSON.generate(meta),
        build: build && JSON.generate(build),
        pending_build_action: pending_build_action&.to_s || 'none',
      }
    end
  end
end
