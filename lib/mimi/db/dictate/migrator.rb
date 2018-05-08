# frozen_string_literal: true

module Mimi
  module DB
    module Dictate
      class Migrator
        DEFAULTS = {
          destructive: {
            tables: false,
            columns: false,
            indexes: false
          },
          dry_run: false,
          logger: nil # will use ActiveRecord::Base.logger
        }.freeze

        attr_reader :table_name, :options, :from_schema, :to_schema

        # Creates a migrator to update table schema from DB state to defined state
        #
        # @param table_name [String,Symbol] table name
        # @param options [Hash]
        #
        def initialize(table_name, options)
          @table_name = table_name
          @options = DEFAULTS.merge(options.dup)
          @from_schema = self.class.db_schema_definition(table_name.to_s)
          @to_schema   = Mimi::DB::Dictate.schema_definitions[table_name.to_s]
          if from_schema.nil? && to_schema.nil?
            raise "Failed to migrate '#{table_name}', no DB or target schema found"
          end
        end

        def logger
          @logger ||= options[:logger] || ActiveRecord::Base.logger
        end

        def db_connection
          ActiveRecord::Base.connection
        end

        # Returns true if the Migrator is configured to do a dry run (no actual changes to DB)
        #
        def dry_run?
          options[:dry_run]
        end

        # Returns true if the Migrator is permitted to do destructive operations (DROP ...)
        # on resources identified by :key
        #
        def destructive?(key)
          options[:destructive] == true ||
            (options[:destructive].is_a?(Hash) && options[:destructive][key])
        end

        def run!
          run_drop_table! if from_schema && to_schema.nil?
          run_change_table! if from_schema && to_schema
          run_create_table! if from_schema.nil? && to_schema
          self.class.reset_db_schema_definition!(table_name)
        end

        def self.db_schema_definition(table_name)
          db_schema_definitions[table_name] ||=
            Mimi::DB::Dictate::Explorer.discover_schema(table_name)
        end

        def self.db_schema_definitions
          @db_schema_definitions ||= {}
        end

        def self.reset_db_schema_definition!(table_name)
          db_schema_definitions[table_name] = nil
        end

        private

        def run_drop_table!
          logger.info "- DROP TABLE: #{table_name}"
          return if dry_run? || !destructive?(:tables)
          db_connection.drop_table(table_name)
        end

        def run_change_table!
          diff = Mimi::DB::Dictate::SchemaDiff.diff(from_schema, to_schema)
          if diff[:columns].empty? && diff[:indexes].empty?
            logger.info "- no changes: #{table_name}"
            return
          end
          logger.info "- ALTER TABLE: #{table_name}"
          run_change_table_columns!(diff[:columns]) unless diff[:columns].empty?
          run_change_table_indexes!(diff[:indexes]) unless diff[:indexes].empty?
        end

        def run_change_table_columns!(diff_columns)
          diff_columns.each do |c, diff|
            drop_column!(table_name, c) if diff[:from] && diff[:to].nil?
            change_column!(table_name, diff[:to]) if diff[:from] && diff[:to]
            add_column!(table_name, diff[:to]) if diff[:from].nil? && diff[:to]
          end
        end

        def run_change_table_indexes!(diff_indexes)
          diff_indexes.each do |i, diff|
            drop_index!(table_name, diff[:from]) if diff[:from] && diff[:to].nil?
            add_index!(table_name, diff[:to]) if diff[:from].nil? && diff[:to]
          end
        end

        def run_create_table!
          columns    = to_schema.columns.values
          column_pk  = to_schema.primary_key
          params =
            column_pk.params.select { |_, v| v }.map { |k, v| "#{k}: #{v.inspect}" }.join(', ')

          # issue CREATE TABLE with primary key field
          logger.info "- CREATE TABLE: #{table_name}"
          logger.info "-- add column: #{table_name}.#{column_pk.name} (#{params})"
          unless dry_run?
            db_connection.create_table(table_name, id: false) do |t|
              t.column column_pk.name, column_pk.type, column_pk.params
            end
          end

          # create rest of the columns and indexes
          (columns - [column_pk]).each { |c| add_column!(table_name, c) }
          to_schema.indexes.each { |i| add_index!(table_name, i) }
        end

        def drop_column!(table_name, column_name)
          logger.info "-- drop column: #{table_name}.#{column_name}"
          return if dry_run? || !destructive?(:columns)
          db_connection.remove_column(table_name, column_name)
        end

        def change_column!(table_name, column)
          params = column.params.select { |_, v| v }.map { |k, v| "#{k}: #{v.inspect}" }.join(', ')
          logger.info "-- change column: #{table_name}.#{column.name} (#{params})"
          return if dry_run?
          db_connection.change_column(table_name, column.name, column.type, column.params)
        end

        def add_column!(table_name, column)
          params = column.params.select { |_, v| v }.map { |k, v| "#{k}: #{v.inspect}" }.join(', ')
          logger.info "-- add column: #{table_name}.#{column.name} (#{params})"
          return if dry_run?
          db_connection.add_column(table_name, column.name, column.type, column.params)
        end

        def drop_index!(table_name, idx)
          idx_column_names = idx.columns.join(', ')
          logger.info "-- drop index: #{idx.name} on #{table_name}(#{idx_column_names})"
          return if dry_run?
          db_connection.remove_index(table_name, column: idx.columns)
        end

        def add_index!(table_name, idx)
          params = idx.params.select { |_, v| v }.map { |k, v| "#{k}: #{v.inspect}" }.join(', ')
          idx_column_names = idx.columns.join(', ')
          logger.info "-- add index: #{idx.name} on #{table_name}(#{idx_column_names}), #{params}"
          return if dry_run?
          db_connection.add_index(table_name, idx.columns, idx.params)
        end
      end # class Migrator
    end # module Dictate
  end # module DB
end # module Mimi
