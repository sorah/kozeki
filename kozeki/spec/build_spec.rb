require 'spec_helper'
require 'tmpdir'
require 'json'

require 'kozeki/build'
require 'kozeki/filesystem'
require 'kozeki/local_filesystem'
require 'kozeki/state'
require 'kozeki/markdown_loader'

RSpec.describe Kozeki::Build do
  let(:tmpdir) do
     d = Dir.mktmpdir
     Dir.mkdir File.join(d, 'src')
     Dir.mkdir File.join(d, 'dst')
     d
  end

  let(:state) { Kozeki::State.open(path: nil) }

  let(:source_filesystem) { Kozeki::LocalFilesystem.new(File.join(tmpdir, 'src')) }
  let(:destination_filesystem) { Kozeki::LocalFilesystem.new(File.join(tmpdir, 'dst')) }

  let(:build) do
    Kozeki::Build.new(
      state:,
      source_filesystem:,
      destination_filesystem:,
      loader: Kozeki::MarkdownLoader,
      incremental_build:,
      events:,
    )
  end

  subject { build.perform }

  def make_markdown(matter, body)
    "#{[
      "---",
      JSON.generate(matter),
      "---",
      "",
      body,
    ].join("\n")}\n"
  end

  def make_record(id, mtime: Time.at(0), meta: {})
    Kozeki::Record.new(
      path: ["#{id}.md"],
      id:,
      timestamp: mtime,
      mtime:,
      meta: meta.merge(id:),
      pending_build_action: nil,
      id_was: nil,
      build: {},
    )
  end

  def read_json(path)
    JSON.parse(File.read(path), symbolize_names: true)
  end

  def assert_dst_files(paths)
    expect(destination_filesystem.list.map { _1.join(File::SEPARATOR) }.sort).to eq(paths.sort)
    expect(paths.sort).to eq(build.updated_files.map { _1.join(File::SEPARATOR)}.sort)
  end

  describe "full build" do
    let(:incremental_build) { false }
    let(:events) { nil }

    let(:now) { Time.now.floor(0) }

    before do
      Dir.mkdir(File.join(tmpdir, 'src', 'a'))
      File.write(File.join(tmpdir, 'src', 'a', '1.md'), make_markdown({id: '1', title: '1', collections: %w(a), timestamp: now.xmlschema}, "1"))
      File.write(File.join(tmpdir, 'src', '2.md'), make_markdown({id: '2', title: '2'}, "2"))
      File.utime(now, now, File.join(tmpdir, 'src', 'a', '1.md'))
    end

    it "builds" do
      subject
      assert_dst_files(%w(
        items/1.json
        items/2.json
        collections/a.json
        collections.json
      ))
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1.json'))).to eq({
        kind: 'item',
        id: '1',
        meta: {
          id: '1',
          title: '1',
          collections: %w(a),
          timestamp: now.xmlschema,
        },
        data: {html: "<p>1</p>\n"},
        kozeki_build: {},
      })

      expect(read_json(File.join(tmpdir, 'dst', 'items', '2.json'))).to eq({
        kind: 'item',
        id: '2',
        meta: {
          id: '2',
          title: '2',
        },
        data: {html: "<p>2</p>\n"},
        kozeki_build: {},
      })

      expect(read_json(File.join(tmpdir, 'dst', 'collections', 'a.json'))).to eq({
        kind: 'collection',
        name: 'a',
        items: [
          {
            id: '1',
            path: 'items/1.json',
            meta: {
              id: '1',
              title: '1',
              collections: %w(a),
              timestamp: now.xmlschema,
            },
          },
        ],
      })

      expect(state.find_record!('1')&.to_h&.slice(:id, :mtime, :path, :pending_build_action, :timestamp)).to eq({
        id: '1',
        mtime: File.mtime(File.join(tmpdir, 'src', 'a', '1.md')),
        path: %w(a 1.md),
        pending_build_action: nil,
        timestamp: Time.at(now.to_i),
      })
      expect(state.find_record!('2')&.to_h&.slice(:id, :path, :pending_build_action)).to eq({
        id: '2',
        path: %w(2.md),
        pending_build_action: nil,
      })
      expect(state.list_collection_names).to eq(%w(a))
      expect(state.list_collection_records('a').map(&:path)).to eq([%w(a 1.md)])
    end
  end

  describe "full build (as a incremental)" do
    let(:incremental_build) { true }
    let(:events) { nil }

    let(:now) { Time.now.floor(0) }

    before do
      Dir.mkdir(File.join(tmpdir, 'src', 'a'))
      File.write(File.join(tmpdir, 'src', 'a', '1.md'), make_markdown({id: '1', title: '1', collections: %w(a), timestamp: now.xmlschema}, "1"))
      File.write(File.join(tmpdir, 'src', '2.md'), make_markdown({id: '2', title: '2'}, "2"))
      File.utime(now, now, File.join(tmpdir, 'src', 'a', '1.md'))
    end

    it "builds" do
      subject
      assert_dst_files(%w(
        items/1.json
        items/2.json
        collections/a.json
        collections.json
      ))
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1.json'))).to eq({
        kind: 'item',
        id: '1',
        meta: {
          id: '1',
          title: '1',
          collections: %w(a),
          timestamp: now.xmlschema,
        },
        data: {html: "<p>1</p>\n"},
        kozeki_build: {},
      })

      expect(read_json(File.join(tmpdir, 'dst', 'items', '2.json'))).to eq({
        kind: 'item',
        id: '2',
        meta: {
          id: '2',
          title: '2',
        },
        data: {html: "<p>2</p>\n"},
        kozeki_build: {},
      })

      expect(read_json(File.join(tmpdir, 'dst', 'collections', 'a.json'))).to eq({
        kind: 'collection',
        name: 'a',
        items: [
          {
            id: '1',
            path: 'items/1.json',
            meta: {
              id: '1',
              title: '1',
              collections: %w(a),
              timestamp: now.xmlschema,
            },
          },
        ],
      })

      expect(state.find_record!('1')&.to_h&.slice(:id, :mtime, :path, :pending_build_action, :timestamp)).to eq({
        id: '1',
        mtime: File.mtime(File.join(tmpdir, 'src', 'a', '1.md')),
        path: %w(a 1.md),
        pending_build_action: nil,
        timestamp: Time.at(now.to_i),
      })
      expect(state.find_record!('2')&.to_h&.slice(:id, :path, :pending_build_action)).to eq({
        id: '2',
        path: %w(2.md),
        pending_build_action: nil,
      })
      expect(state.list_collection_names).to eq(%w(a))
      expect(state.list_collection_records('a').map(&:path)).to eq([%w(a 1.md)])
    end
  end

  describe "incremental build (nothing)" do
    let(:incremental_build) { true }
    let(:events) { [] }

    before do
      File.write(File.join(tmpdir, 'src', '1.md'), make_markdown({id: '1', collections: %w(a)}, "1"))
      state.set_record_collections_pending('1', %w(a))
      state.save_record(make_record('1'))
      state.process_markers!
      state.mark_build_completed(state.create_build)
    end

    it "does nothing" do
      subject
      assert_dst_files([])

      expect(state.find_record!('1')&.to_h&.slice(:id, :path)).to eq({
        id: '1',
        path: %w(1.md),
      })
      expect(state.list_collection_names).to eq(%w(a))
      expect(state.list_collection_records('a').map(&:path)).to eq([%w(1.md)])
    end
  end

  describe "incremental build (update)" do
    let(:incremental_build) { true }

    let(:events) do
      [
        Kozeki::Filesystem::Event.new(op: :update, path: ['1.md'], time: nil),
      ]
    end

    before do
      File.write(File.join(tmpdir, 'src', '1.md'), make_markdown({id: '1', collections: %w(a b)}, "1"))
      state.mark_build_completed(state.create_build)
      state.save_record(make_record('1'))
    end

    it "builds" do
      subject
      assert_dst_files(%w(
        items/1.json
        collections/a.json
        collections/b.json
        collections.json
      ))
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1.json'))).to eq({
        kind: 'item',
        id: '1',
        meta: {
          id: '1',
          collections: %w(a b),
        },
        data: {html: "<p>1</p>\n"},
        kozeki_build: {},
      })
      expect(read_json(File.join(tmpdir, 'dst', 'collections', 'a.json'))).to eq({
        kind: 'collection',
        name: 'a',
        items: [
          {
            id: '1',
            path: 'items/1.json',
            meta: {
              id: '1',
              collections: %w(a b),
            },
          },
        ],
      })
      expect(read_json(File.join(tmpdir, 'dst', 'collections', 'b.json'))).to eq({
        kind: 'collection',
        name: 'b',
        items: [
          {
            id: '1',
            path: 'items/1.json',
            meta: {
              id: '1',
              collections: %w(a b),
            },
          },
        ],
      })

      expect(state.find_record!('1').mtime.floor).to eq(File.mtime(File.join(tmpdir, 'src', '1.md')).floor)
    end
  end

  describe "incremental build (delete)" do
    let(:incremental_build) { true }

    let(:events) do
      [
        Kozeki::Filesystem::Event.new(op: :delete, path: ['1.md'], time: nil),
      ]
    end

    before do
      FileUtils.mkdir_p(File.join(tmpdir, 'dst', 'items'))
      FileUtils.mkdir_p(File.join(tmpdir, 'dst', 'collections'))
      File.write(File.join(tmpdir, 'dst', 'items', '1.json'), "{}\n")
      File.write(File.join(tmpdir, 'dst', 'collections', 'a.json'), "{}\n")
      state.save_record(make_record('1', meta: {collections: %w(a)}))
      state.set_record_collections_pending('1', %w(a))
      state.process_markers!
      state.mark_build_completed(state.create_build)
    end

    it "builds" do
      subject
      assert_dst_files(%w(collections.json))
      expect { state.find_record!('1') }.to raise_error(Kozeki::State::NotFound)
      expect(state.list_collection_names).to eq([])
    end
  end

  describe "incremental build (mtime based update)" do
    let(:incremental_build) { true }
    let(:events) { nil }
    let(:t) { Time.now.floor - 600 }

    before do
      File.write(File.join(tmpdir, 'src', '1.md'), make_markdown({id: '1', collections: %w(a)}, "1"))
      File.write(File.join(tmpdir, 'src', '2.md'), make_markdown({id: '2', meta: 2}, "2"))
      File.utime(t+60, t+60, File.join(tmpdir, 'src', '1.md'))
      File.utime(t, t, File.join(tmpdir, 'src', '2.md'))
      state.save_record(make_record('1', meta: {collections: %w(a)}, mtime: t.to_i))
      state.set_record_collections_pending('1', %w(a))
      state.save_record(make_record('2', mtime: t.to_i))
      state.process_markers!
      state.mark_build_completed(state.create_build)
    end

    it "builds" do
      subject
      assert_dst_files(%w(items/1.json collections/a.json collections.json))
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1.json'))).to eq({
        kind: 'item',
        id: '1',
        meta: {
          id: '1',
          collections: %w(a),
        },
        data: {html: "<p>1</p>\n"},
        kozeki_build: {},
      })
      expect(read_json(File.join(tmpdir, 'dst', 'collections', 'a.json'))).to eq({
        kind: 'collection',
        name: 'a',
        items: [
          {
            id: '1',
            path: 'items/1.json',
            meta: {
              id: '1',
              collections: %w(a),
            },
          },
        ],
      })
      expect(state.find_record!('1').mtime.floor).to eq(t+60)
      expect(state.find_record!('2').mtime.floor).to eq(t)
      expect(state.find_record!('2').meta[:meta]).to eq(nil)
    end
  end

  describe "incremental build (mtime based delete)" do
    let(:incremental_build) { true }
    let(:events) { nil }

    before do
      t = Time.now.round - 600
      Dir.mkdir(File.join(tmpdir, 'dst', 'items'))
      Dir.mkdir(File.join(tmpdir, 'dst', 'collections'))
      File.write(File.join(tmpdir, 'src', '2.md'), make_markdown({id: '2'}, "2"))
      File.utime(t, t, File.join(tmpdir, 'src', '2.md'))
      File.write(File.join(tmpdir, 'dst', 'items', '1.json'), "{}\n")
      File.write(File.join(tmpdir, 'dst', 'collections', 'a.json'), "{}\n")
      state.save_record(make_record('1', meta: {collections: %w(a)}, mtime: t))
      state.set_record_collections_pending('1', %w(a))
      state.save_record(make_record('2', mtime: t))
      state.process_markers!
      state.mark_build_completed(state.create_build)
    end

    it "builds" do
      subject
      assert_dst_files(%w(collections.json))
      expect { state.find_record!('1') }.to raise_error(Kozeki::State::NotFound)
      expect(state.list_collection_names).to eq([])
    end
  end

  describe "incremental build (ID change)" do
    let(:incremental_build) { true }
    let(:events) do
      [
        Kozeki::Filesystem::Event.new(op: :update, path: ['1.md'], time: nil),
      ]
    end

    before do
      Dir.mkdir(File.join(tmpdir, 'dst', 'items'))
      File.write(File.join(tmpdir, 'src', '1.md'), make_markdown({id: '1x', collections: %w(a)}, "1"))
      File.write(File.join(tmpdir, 'dst', 'items', '1.json'), "{}\n")
      state.mark_build_completed(state.create_build)
      state.save_record(make_record('1'))
    end

    it "builds" do
      subject
      assert_dst_files(%w(
        items/1x.json
        collections/a.json
        collections.json
      ))
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1x.json'))).to eq({
        kind: 'item',
        id: '1x',
        meta: {
          id: '1x',
          collections: %w(a),
        },
        data: {html: "<p>1</p>\n"},
        kozeki_build: {},
      })
      expect(read_json(File.join(tmpdir, 'dst', 'collections', 'a.json'))).to eq({
        kind: 'collection',
        name: 'a',
        items: [
          {
            id: '1x',
            path: 'items/1x.json',
            meta: {
              id: '1x',
              collections: %w(a),
            },
          },
        ],
      })

      expect { state.find_record!('1') }.to raise_error(Kozeki::State::NotFound)
      expect(state.find_record!('1x').path).to eq(%w(1.md))
    end
  end

  describe "incremental build (ID conflict)" do
    let(:incremental_build) { true }
    let(:events) do
      [
        Kozeki::Filesystem::Event.new(op: :update, path: ['1.md'], time: nil),
      ]
    end

    before do
      File.write(File.join(tmpdir, 'src', '1.md'), make_markdown({id: '2', collections: %w(a)}, "1"))
      state.mark_build_completed(state.create_build)
      state.save_record(make_record('2'))
    end

    it "refuses to build" do
      expect { subject }.to raise_error(Kozeki::State::DuplicatedItemIdError)
      assert_dst_files(%w())
      expect { state.find_record!('2') }.to raise_error(Kozeki::State::DuplicatedItemIdError)
      expect(state.list_records_by_id('2').map(&:path).sort).to eq([%w(1.md), %w(2.md)])
    end

    describe "recovery" do
      let(:events) do
        [
          Kozeki::Filesystem::Event.new(op: :delete, path: ['2.md'], time: nil),
        ]
      end

      before do
        state.db.execute(%{insert into "records" ("path", "id", "pending_build_action", "timestamp", "mtime", "meta") values ('1.md', '2', 'update', 0, 0, '{"id": "2", "collections": ["a"]}')})
      end

      it "can recover" do
        subject
        assert_dst_files(%w(
          items/2.json
          collections/a.json
          collections.json
        ))
        expect(read_json(File.join(tmpdir, 'dst', 'items', '2.json'))).to eq({
          kind: 'item',
          id: '2',
          meta: {
            id: '2',
            collections: %w(a),
          },
          data: {html: "<p>1</p>\n"},
          kozeki_build: {},
        })
        expect(read_json(File.join(tmpdir, 'dst', 'collections', 'a.json'))).to eq({
          kind: 'collection',
          name: 'a',
          items: [
            {
              id: '2',
              path: 'items/2.json',
              meta: {
                id: '2',
                collections: %w(a),
              },
            },
          ],
        })

        expect(state.find_record!('2')&.to_h&.slice(:id, :path, :pending_build_action)).to eq({
          id: '2',
          path: %w(1.md),
          pending_build_action: nil,
        })
        expect(state.list_collection_names).to eq(%w(a))
        expect(state.list_collection_records('a').map(&:path)).to eq([%w(1.md)])
      end
    end
  end

  describe "incremental build (file rename by create then delete)" do
    let(:incremental_build) { true }
    let(:events) do
      [
        Kozeki::Filesystem::Event.new(op: :update, path: ['1x.md'], time: nil),
        Kozeki::Filesystem::Event.new(op: :delete, path: ['1.md'], time: nil),
      ]
    end

    before do
      File.write(File.join(tmpdir, 'src', '1x.md'), make_markdown({id: '1', collections: %w(a)}, "1"))
      state.save_record(make_record('1'))
      state.set_record_collections_pending('1', %w(a))
      state.process_markers!
      state.mark_build_completed(state.create_build)
    end

    it "builds" do
      subject
      assert_dst_files(%w(
        items/1.json
        collections/a.json
        collections.json
      ))
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1.json'))).to eq({
        kind: 'item',
        id: '1',
        meta: {
          id: '1',
          collections: %w(a),
        },
        data: {html: "<p>1</p>\n"},
        kozeki_build: {},
      })
      expect(read_json(File.join(tmpdir, 'dst', 'collections', 'a.json'))).to eq({
        kind: 'collection',
        name: 'a',
        items: [
          {
            id: '1',
            path: 'items/1.json',
            meta: {
              id: '1',
              collections: %w(a),
            },
          },
        ],
      })

      expect(state.find_record!('1').path).to eq(%w(1x.md))
    end
  end

  describe "incremental build (file rename by delete then create)" do
    let(:incremental_build) { true }
    let(:events) do
      [
        Kozeki::Filesystem::Event.new(op: :delete, path: ['1.md'], time: nil),
        Kozeki::Filesystem::Event.new(op: :update, path: ['1x.md'], time: nil),
      ]
    end

    before do
      File.write(File.join(tmpdir, 'src', '1x.md'), make_markdown({id: '1', collections: %w(a)}, "1"))
      state.save_record(make_record('1'))
      state.set_record_collections_pending('1', %w(a))
      state.process_markers!
      state.mark_build_completed(state.create_build)
    end

    it "builds" do
      subject
      assert_dst_files(%w(
        items/1.json
        collections/a.json
        collections.json
      ))
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1.json'))).to eq({
        kind: 'item',
        id: '1',
        meta: {
          id: '1',
          collections: %w(a),
        },
        data: {html: "<p>1</p>\n"},
        kozeki_build: {},
      })
      expect(read_json(File.join(tmpdir, 'dst', 'collections', 'a.json'))).to eq({
        kind: 'collection',
        name: 'a',
        items: [
          {
            id: '1',
            path: 'items/1.json',
            meta: {
              id: '1',
              collections: %w(a),
            },
          },
        ],
      })

      expect(state.find_record!('1').path).to eq(%w(1x.md))
    end
  end

end
