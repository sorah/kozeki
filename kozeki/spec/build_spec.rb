require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'

require 'kozeki/build'
require 'kozeki/config'
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

  let(:collection_options) { [] }

  let(:build) do
    Kozeki::Build.new(
      state:,
      source_filesystem:,
      destination_filesystem:,
      loader: Kozeki::MarkdownLoader,
      collection_options:,
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


  def make_rendered_header(matter, body)
    {
      id: matter.fetch(:id),
      path: "items/#{matter.fetch(:id)}.json",
      meta: matter,
    }
  end

  def make_rendered_item(matter, body)
    {
      kind: 'item',
      id: matter.fetch(:id),
      meta: matter,
      data: {html: "<p>#{body}</p>\n"},
      kozeki_build: {},
    }
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
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1.json'))).to eq(make_rendered_item({id: '1', title: '1', collections: %w(a), timestamp: now.xmlschema}, "1"))
      expect(read_json(File.join(tmpdir, 'dst', 'items', '2.json'))).to eq(make_rendered_item({id: '2', title: '2'}, "2"))

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
      File.write(File.join(tmpdir, 'dst', 'mark'), "\n")
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
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1.json'))).to eq(make_rendered_item({id: '1', title: '1', collections: %w(a), timestamp: now.xmlschema}, "1"))
      expect(read_json(File.join(tmpdir, 'dst', 'items', '2.json'))).to eq(make_rendered_item({id: '2', title: '2'}, "2"))

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
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1.json'))).to eq(make_rendered_item({id: '1', collections: %w(a b)}, "1"))
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
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1.json'))).to eq(make_rendered_item({id: '1', collections: %w(a)}, "1"))
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
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1x.json'))).to eq(make_rendered_item({id: '1x', collections: %w(a)}, "1"))
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
        expect(read_json(File.join(tmpdir, 'dst', 'items', '2.json'))).to eq(make_rendered_item({id: '2', collections: %w(a)}, "1"))
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
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1.json'))).to eq(make_rendered_item({id: '1', collections: %w(a)}, "1"))
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
      expect(read_json(File.join(tmpdir, 'dst', 'items', '1.json'))).to eq(make_rendered_item({id: '1', collections: %w(a)}, "1"))
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

  describe "Collection" do
    let(:incremental_build) { false }
    let(:events) { nil }
    let(:now) { Time.now.floor(0) }

    before do
      (1..10).each do |i|
        File.write(File.join(tmpdir, 'src', "#{i}.md"), make_markdown({id: i.to_s,  collections: %w(a), timestamp: (now-i).xmlschema}, i.to_s))
      end
    end

    describe "max_items" do
      let(:collection_options) do
        [
          Kozeki::Config::CollectionOptions.new(
            prefix: 'a',
            max_items: 5,
          ),
        ]
      end

      it "builds" do
        subject

        expect(read_json(File.join(tmpdir, 'dst', 'collections', 'a.json'))).to eq({
          kind: 'collection',
          name: 'a',
          items: (1..5).map do |i|
            make_rendered_header({id: i.to_s,  collections: %w(a), timestamp: (now-i).xmlschema}, i.to_s)
          end,
        })
      end
    end

    describe "paginate" do
      let(:collection_options) do
        [
          Kozeki::Config::CollectionOptions.new(
            prefix: 'a',
            max_items: 3,
            paginate: true,
          ),
        ]
      end

      it "builds" do
        subject

        make_info = ->(pagenum) do
          j={
            first: "collections/a.json",
            last: "collections/a/page-4.json",
            prev: pagenum > 1 ? "collections/a/page-#{pagenum-1}.json" : nil,
            next: pagenum < 4 ? "collections/a/page-#{pagenum+1}.json" : nil,
            self: pagenum,
            total_pages: 4,
          }
          if pagenum == 1
            j.merge!(pages: ["collections/a.json", "collections/a/page-2.json", "collections/a/page-3.json", "collections/a/page-4.json"])
          end
          if pagenum == 2
            j.merge!(prev: "collections/a.json")
          end
          j
        end

        expect(read_json(File.join(tmpdir, 'dst', 'collections', 'a.json'))).to eq({
          kind: 'collection',
          name: 'a',
          items: (1..3).map do |i|
            make_rendered_header({id: i.to_s,  collections: %w(a), timestamp: (now-i).xmlschema}, i.to_s)
          end,
          page: make_info[1],
        })
        expect(read_json(File.join(tmpdir, 'dst', 'collections', 'a', 'page-2.json'))).to eq({
          kind: 'collection',
          name: 'a',
          items: (4..6).map do |i|
            make_rendered_header({id: i.to_s,  collections: %w(a), timestamp: (now-i).xmlschema}, i.to_s)
          end,
          page: make_info[2],
        })
        expect(read_json(File.join(tmpdir, 'dst', 'collections', 'a', 'page-3.json'))).to eq({
          kind: 'collection',
          name: 'a',
          items: (7..9).map do |i|
            make_rendered_header({id: i.to_s,  collections: %w(a), timestamp: (now-i).xmlschema}, i.to_s)
          end,
          page: make_info[3],
        })
        expect(read_json(File.join(tmpdir, 'dst', 'collections', 'a', 'page-4.json'))).to eq({
          kind: 'collection',
          name: 'a',
          items: (10..10).map do |i|
            make_rendered_header({id: i.to_s,  collections: %w(a), timestamp: (now-i).xmlschema}, i.to_s)
          end,
          page: make_info[4],
        })
      end
    end

    describe "paginate, when page removed" do
      let(:collection_options) do
        [
          Kozeki::Config::CollectionOptions.new(
            prefix: 'a',
            max_items: 3,
            paginate: true,
          ),
        ]
      end

      let(:incremental_build) { true }
      let(:events) do
        [
          Kozeki::Filesystem::Event.new(op: :delete, path: ['10.md'], time: nil),
        ]
      end

      before do
        FileUtils.mkdir_p(File.join(tmpdir, 'dst', 'collections', 'a'))
        File.write(File.join(tmpdir, 'dst', 'collections', 'a', 'page-4.json'), "{}\n")
        (1..10).each do |i|
          state.set_record_collections_pending(i.to_s, %w(a))
          state.save_record(make_record(i.to_s))
        end
        state.process_markers!
        state.mark_build_completed(state.create_build)
      end

      it "builds" do
        subject
        assert_dst_files(%w(
          collections.json
          collections/a.json
          collections/a/page-2.json
          collections/a/page-3.json
        ))
      end
    end

  end
end
