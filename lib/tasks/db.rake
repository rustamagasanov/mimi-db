namespace :db do
  #
  # A task that ensures the application is configured and the database connection started
  #
  task start: :"application:configure" do
    Mimi::DB.start
  end

  desc 'Show database config'
  task config: :"application:configure" do
    Mimi::DB.active_record_config.each do |k, v|
      puts "#{k}: #{v}"
    end
  end

  desc 'Create database'
  task create: :"application:configure" do
    logger.info "* Creating database #{Mimi::DB.module_options[:db_database]}"
    Mimi::DB.create!
  end

  desc 'Clear database'
  task clear: :"application:configure" do
    logger.info "* Clearing database #{Mimi::DB.module_options[:db_database]}"
    Mimi::DB.clear!
  end

  desc 'Drop database'
  task drop: :"application:configure" do
    logger.info "* Dropping database #{Mimi::DB.module_options[:db_database]}"
    Mimi::DB.drop!
  end

  desc 'Migrate database (schema and seeds)'
  task migrate: :"db:start" do
    Rake::Task[:"db:migrate:schema"].invoke
    Rake::Task[:"db:migrate:seeds"].invoke
  end

  namespace :migrate do
    desc 'Migrate database (seeds only)'
    task seeds: :"db:start" do
      seeds = Pathname.glob(Mimi.app_path_to('db', 'seeds', '**', '*.rb')).sort
      seeds.each do |seed_filename|
        logger.info "* Processing seed: #{seed_filename}"
        load seed_filename
      end
    end

    desc 'Migrate database (schema only)'
    task schema: :"db:start" do
      logger.info "* Updating database schema: #{Mimi::DB.module_options[:db_database]}"
      Mimi::DB.update_schema!(destructive: true)
    end

    namespace :schema do
      desc 'Migrate database (schema only) (DRY RUN)'
      task dry_run: :"db:start" do
        logger.info "* Updating database schema (DRY RUN): #{Mimi::DB.module_options[:db_database]}"
        Mimi::DB.update_schema!(destructive: true, dry_run: true)
      end

      desc 'Display differences between existing DB schema and target schema'
      task diff: :"db:start" do
        logger.info "* Diff database schema: #{Mimi::DB.module_options[:db_database]}"
        diff = Mimi::DB.diff_schema(destructive: true, dry_run: true)
        require 'pp'
        pp diff
      end
    end
  end
end
