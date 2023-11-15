# frozen_string_literal: true

require 'sqlite3'
require 'fileutils'

require 'kozeki/record'

module Kozeki
  class State
    EPOCH = 1

    class NotFound < StandardError; end
    class DuplicatedItemIdError < StandardError; end

    def self.open(path:)
      FileUtils.mkdir_p File.dirname(path) if path
      state = new(path:)
      state.ensure_schema!
      state
    end

    # @param path [String, #to_path, nil]
    def initialize(path:)
      @db = SQLite3::Database.new(
        path || ':memory:',
        {
          results_as_hash: true,
          strict: true, # Disable SQLITE_DBCONFIG_DQS_DDL, SQLITE_DBCONFIG_DQS_DML
        }
      )
    end

    attr_reader :db

    def clear!
      @db.execute_batch <<~SQL
        delete from "records";
        delete from "collection_memberships";
        delete from "item_ids";
        delete from "builds";
      SQL
    end

    def build_exist?
      @db.execute(%{select * from "builds" where completed = 1 limit 1})[0]
    end

    def create_build(t = Time.now)
      @db.execute(%{insert into "builds" ("built_at") values (?)}, [t.to_i])
      @db.last_insert_row_id
    end

    # @param id [id]
    def mark_build_completed(id)
      @db.execute(%{update "builds" set completed = 1 where id = ?}, [id])
    end

    # Clear all markers and delete 'remove'd rows.
    def process_markers!
      @db.execute_batch <<~SQL
        delete from "records" where "pending_build_action" = 'remove';
        update "records" set "pending_build_action" = 'none', "id_was" = null where "pending_build_action" <> 'none';
        delete from "collection_memberships" where "pending_build_action" = 'remove';
        update "collection_memberships" set "pending_build_action" = 'none' where "pending_build_action" <> 'none';
        delete from "item_ids" where "pending_build_action" = 'remove';
        update "item_ids" set "pending_build_action" = 'none' where "pending_build_action" <> 'none';
      SQL
    end

    # @param path [Array<String>]
    def find_record_by_path!(path)
      row = @db.execute(%{select * from "records" where "path" = ?}, [path.join('/')])[0]
      if row
        Record.from_row(row)
      else
        raise NotFound, "record not found for path=#{path.inspect}"
      end
    end

    def find_record!(id)
      rows = @db.execute(%{select * from "records" where "id" = ? and "pending_build_action" <> 'remove'}, [id])
      case rows.size
      when 0
        raise NotFound, "record not found for id=#{id.inspect}"
      when 1
        Record.from_row(rows[0])
      else
        raise DuplicatedItemIdError, "multiple records found for id=#{id.inspect}, resolve conflict first"
      end
    end

    def list_records_by_pending_build_action(action)
      rows = @db.execute(%{select * from "records" where "pending_build_action" = ?}, [action.to_s])
      rows.map { Record.from_row(_1) }
    end

    def list_records_by_id(id)
      rows = @db.execute(%{select * from "records" where "id" = ?}, [id.to_s])
      rows.map { Record.from_row(_1) }
    end

    def list_record_paths
      rows = @db.execute(%{select "path" from "records"})
      rows.map { _1.fetch('path').split('/') } # XXX: consolidate with Record logic
    end

    # @param record [Record]
    def save_record(record)
      new_row = @db.execute(<<~SQL, record.to_row)[0]
         insert into "records"
           ("path", "id", "timestamp", "mtime", "meta", "build", "pending_build_action")
         values
           (:path, :id, :timestamp, :mtime, :meta, :build, :pending_build_action)
         on conflict ("path") do update set
           "id" = excluded."id"
         , "timestamp" = excluded."timestamp"
         , "mtime" = excluded."mtime"
         , "meta" = excluded."meta"
         , "build" = excluded."build"
         , "pending_build_action" = excluded."pending_build_action"
         , "id_was" = "id"
         returning
           *
      SQL
      id_was = new_row['id_was']
      @db.execute(<<~SQL, [record.id])
        insert into "item_ids" ("id") values (?)
        on conflict ("id") do update set
          "pending_build_action" = 'none'
      SQL
      case id_was
      when record.id
        record
      when nil
        record
      else
        @db.execute(<<~SQL, [id_was])
          insert into "item_ids" ("id") values (?)
          on conflict ("id") do update set
            "pending_build_action" = 'garbage_collection'
        SQL
        Record.from_row(new_row)
      end
    end

    def set_record_pending_build_action(record, pending_build_action)
      path = record.path
      @db.execute(<<~SQL, {path: record.path_row, pending_build_action: pending_build_action.to_s})
        update "records"
        set "pending_build_action" = :pending_build_action
        where "path" = :path
      SQL
      raise NotFound, "record not found to update for path=#{path}" if @db.changes.zero?
      if pending_build_action == :remove
        @db.execute(<<~SQL, [record.id])
          update "item_ids"
          set "pending_build_action" = 'garbage_collection'
          where "id" = :id
        SQL
      end
      nil
    end

    def set_record_collections_pending(record_id, collections)
      @db.execute(%{update "collection_memberships" set pending_build_action = 'remove' where record_id = ?}, record_id)
      return if collections.empty?
      @db.execute(<<~SQL, collections.map { [_1, record_id, 'update'] })
        insert into "collection_memberships"
          ("collection", "record_id", "pending_build_action")
        values
          #{collections.map { '(?,?,?)' }.join(',')}
        on conflict ("collection", "record_id") do update set
          "pending_build_action" = excluded."pending_build_action"
      SQL
    end

    def list_item_ids_for_garbage_collection
      @db.execute(%{select "id" from "item_ids" where "pending_build_action" = 'garbage_collection'}).map do |row|
        row.fetch('id')
      end
    end

    def mark_item_id_to_remove(id)
      @db.execute(%{update "item_ids" set "pending_build_action" = 'remove' where "id" = ?}, [id])
      nil
    end

    def list_collection_names_pending
      @db.execute(%{select distinct "collection" from "collection_memberships" where "pending_build_action" <> 'none'}).map do |row|
        row.fetch('collection')
      end
    end

    def list_collection_names
      @db.execute(%{select distinct "collection" from "collection_memberships"}).map do |row|
        row.fetch('collection')
      end
    end

    def list_collection_names_with_prefix(*prefixes)
      return list_collection_names() if prefixes.empty?
      conditions = prefixes.map { %{"collection" glob '#{SQLite3::Database.quote(_1)}*'} }
      @db.execute(%{select distinct "collection" from "collection_memberships" where (#{conditions.join('or')}) and "pending_build_action" <> 'remove'}).map do |row|
        row.fetch('collection')
      end
    end


    def list_collection_records(collection)
      @db.execute(<<~SQL, [collection]).map { Record.from_row(_1) }
        select
          "records".*
        from "collection_memberships"
        inner join "records" on "collection_memberships"."record_id" = "records"."id"
        where
          "collection_memberships"."collection" = ?
          and "collection_memberships"."pending_build_action" <> 'remove'
          and "records"."pending_build_action" <> 'remove'
      SQL
    end

    def count_collection_records(collection)
      @db.execute(<<~SQL, [collection])[0].fetch('cnt')
        select
          count(*) cnt
        from "collection_memberships"
        where
          "collection_memberships"."collection" = ?
      SQL
    end

    def transaction(...)
      db.transaction(...)
    end

    def close
      db.close
    end

    # Ensure schema for the present version of Kozeki. As a state behaves like a cache, all tables will be removed
    # when version is different.
    def ensure_schema!
      return if current_epoch == EPOCH

      db.execute_batch <<~SQL
        drop table if exists "kozeki_schema_epoch";
        create table kozeki_schema_epoch (
          "epoch" integer not null
        ) strict;
      SQL

      db.execute_batch <<~SQL
        drop table if exists "records";
        create table "records" (
          path text not null unique,
          id text not null,
          timestamp integer not null,
          mtime integer not null,
          meta text not null,
          build text,
          pending_build_action text not null default 'none',
          id_was text
        ) strict;
      SQL
      # Non-unique index; during normal file operation we may see duplicated IDs while we process events one-by-one
      db.execute_batch <<~SQL
        drop index if exists "idx_records_id";
        create index "idx_records_id" on "records" ("id");
      SQL
      db.execute_batch <<~SQL
        drop index if exists "idx_records_pending";
        create index "idx_records_pending" on "records" ("pending_build_action");
      SQL

      db.execute_batch <<~SQL
        drop table if exists "item_ids";
        create table "item_ids" (
          id text unique not null,
          pending_build_action text not null default 'none'
        ) strict;
      SQL
      db.execute_batch <<~SQL
        drop index if exists "idx_item_ids_pending";
        create index "idx_item_ids_pending" on "item_ids" ("pending_build_action");
      SQL

      db.execute_batch <<~SQL
        drop table if exists "collection_memberships";
        create table "collection_memberships" (
          collection text not null,
          record_id text not null,
          pending_build_action text not null default 'none'
        ) strict;
      SQL
      db.execute_batch <<~SQL
        drop index if exists "idx_col_record";
        create unique index "idx_col_record" on "collection_memberships" ("collection", "record_id");
      SQL
      db.execute_batch <<~SQL
        drop index if exists "idx_col_pending";
        create index "idx_col_pending" on "collection_memberships" ("pending_build_action", "collection");
      SQL

      db.execute_batch <<~SQL
        drop table if exists "builds";
        create table "builds" (
          id integer primary key,
          built_at integer not null,
          completed integer not null default 0
        ) strict;
      SQL

      db.execute(%{delete from "kozeki_schema_epoch"})
      db.execute(%{insert into "kozeki_schema_epoch" values (?)}, [EPOCH])

      nil
    end

    def current_epoch
      epoch_tables = @db.execute("select * from sqlite_schema where type = 'table' and name = 'kozeki_schema_epoch'")
      return nil if epoch_tables.empty?
      epoch = @db.execute(%{select "epoch" from "kozeki_schema_epoch" order by "epoch" desc limit 1})
      epoch&.dig(0, 'epoch')
    end
  end
end
