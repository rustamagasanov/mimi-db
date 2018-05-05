module Mimi
  module DB
    module Helpers
      #
      # Returns a list of model classes
      #
      # @return [Array<ActiveRecord::Base>]
      #
      def models
        ActiveRecord::Base.descendants
      end

      # Returns a list of table names defined in models
      #
      # @return [Array<String>]
      #
      def model_table_names
        models.map(&:table_name).uniq
      end

      # Returns a list of all DB table names
      #
      # @return [Array<String>]
      #
      def db_table_names
        ActiveRecord::Base.connection.tables
      end

      # Returns a list of all discovered table names,
      # both defined in models and existing in DB
      #
      # @return [Array<String>]
      #
      def all_table_names
        (model_table_names + db_table_names).uniq
      end

      # Updates the DB schema.
      #
      # Brings DB schema to a state defined in models.
      #
      # Default options from Migrator::DEFAULTS:
      #     destructive: {
      #       tables: false,
      #       columns: false,
      #       indexes: false
      #     },
      #     dry_run: false,
      #     logger: nil # will use ActiveRecord::Base.logger
      #
      # @example
      #   # only detect and report planned changes
      #   Mimi::DB.update_schema!(dry_run: true)
      #
      #   # modify the DB schema, including all destructive operations
      #   Mimi::DB.update_schema!(destructive: true)
      #
      def update_schema!(opts = {})
        opts[:logger] ||= Mimi::DB.logger
        Mimi::DB::Dictate.update_schema!(opts)
      end

      # Creates the database specified in the current configuration.
      #
      def create!
        db_adapter = Mimi::DB.active_record_config['adapter']
        db_database = Mimi::DB.active_record_config['database']
        slim_url = "#{db_adapter}//<host>:<port>/#{db_database}"
        Mimi::DB.logger.info "Mimi::DB.create! creating database: #{slim_url}"
        original_stdout = $stdout
        original_stderr = $stderr
        $stdout = StringIO.new
        $stderr = StringIO.new
        ActiveRecord::Tasks::DatabaseTasks.root = Mimi.app_root_path
        ActiveRecord::Tasks::DatabaseTasks.create(Mimi::DB.active_record_config)
        Mimi::DB.logger.debug "Mimi::DB.create! out:#{$stdout.string}, err:#{$stderr.string}"
      ensure
        $stdout = original_stdout
        $stderr = original_stderr
      end

      # Tries to establish connection, returns true if the database exist
      #
      def database_exist?
        ActiveRecord::Base.establish_connection(Mimi::DB.active_record_config)
        ActiveRecord::Base.connection
        true
      rescue ActiveRecord::NoDatabaseError
        false
      end

      # Creates the database specified in the current configuration, if it does NOT exist.
      #
      def create_if_not_exist!
        if database_exist?
          Mimi::DB.logger.debug 'Mimi::DB.create_if_not_exist! database exists, skipping...'
          return
        end
        create!
      end

      # Drops the database specified in the current configuration.
      #
      def drop!
        original_stdout = $stdout
        original_stderr = $stderr
        $stdout = StringIO.new
        $stderr = StringIO.new
        ActiveRecord::Tasks::DatabaseTasks.root = Mimi.app_root_path
        ActiveRecord::Tasks::DatabaseTasks.drop(Mimi::DB.active_record_config)
        Mimi::DB.logger.debug "Mimi::DB.drop! out:#{$stdout.string}, err:#{$stderr.string}"
      ensure
        $stdout = original_stdout
        $stderr = original_stderr
      end

      # Clears (but not drops) the database specified in the current configuration.
      #
      def clear!
        original_stdout = $stdout
        original_stderr = $stderr
        $stdout = StringIO.new
        $stderr = StringIO.new
        ActiveRecord::Tasks::DatabaseTasks.root = Mimi.app_root_path
        ActiveRecord::Tasks::DatabaseTasks.purge(Mimi::DB.active_record_config)
        Mimi::DB.logger.debug "Mimi::DB.clear! out:#{$stdout.string}, err:#{$stderr.string}"
      ensure
        $stdout = original_stdout
        $stderr = original_stderr
      end

      # Executes raw SQL, with variables interpolation.
      #
      # @example
      #   Mimi::DB.execute('insert into table1 values(?, ?, ?)', 'foo', :bar, 123)
      #
      def execute(statement, *args)
        sql = ActiveRecord::Base.send(:replace_bind_variables, statement, args)
        ActiveRecord::Base.connection.execute(sql)
      end
    end # module Helpers

    extend Mimi::DB::Helpers
  end # module DB
end # module Mimi
