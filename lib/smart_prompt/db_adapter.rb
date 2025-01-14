require "sequel"
require "json"

module SmartPrompt
  class DBAdapter
    attr_reader :db, :tables
    def initialize(config)
      db_uri = config[:database]
      @db = Sequel.connect(db_uri)
      @tables = {}
      @db.tables.each do |table_name|
        define_table(table_name)
      end
    end

    def define_table(table_name, class_name=table_name.to_s.capitalize)
      class_define = <<-EOT
        class #{class_name} < Sequel::Model(:#{table_name})
        end
      EOT
      eval(class_define)
      @tables[table_name] = eval(class_name)
    end

    def get_table_schema(table_name)
      @tables[table_name].db_schema
    end

    def get_table_schema_str(table_name)
      JSON.pretty_generate(get_table_schema(table_name))
    end

    def get_db_schema
      schema = {}
      @db.tables.each do |table_name|
        schema[table_name] = get_table_schema(table_name)
      end
      schema
    end

    def get_db_schema_str
      JSON.pretty_generate(get_db_schema)
    end
  end
end