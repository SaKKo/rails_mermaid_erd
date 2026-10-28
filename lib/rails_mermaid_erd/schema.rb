# frozen_string_literal: true

module RailsMermaidErd
  # Reads column types from db/schema.rb (only used to label the foreign-key
  # attributes that get drawn). Missing schema is fine: types fall back to
  # bigint / string.
  class Schema
    def self.load(path)
      return new({}) unless path && File.exist?(path)

      new(parse(File.read(path)))
    end

    def self.parse(source)
      tables = {}
      current = nil
      source.each_line do |line|
        if (m = line.match(/^\s*create_table\s+["':]?([\w.]+)["']?(.*)$/))
          current = tables[m[1].split(".").last] = {}
          current["id"] = id_type(m[2])
        elsif line.match?(/^\s*end\b/)
          current = nil
        elsif current && (m = line.match(/^\s*t\.(\w+)\s+["':]?(\w+)["']?(.*)$/))
          type, col, rest = m[1], m[2], m[3]
          if %w[references belongs_to].include?(type)
            current["#{col}_id"] = rest[/type:\s*:?["']?(\w+)/, 1] || "bigint"
            current["#{col}_type"] = "string" if rest.include?("polymorphic: true")
          else
            current[col] = type
          end
        end
      end
      tables
    end

    def self.id_type(rest)
      return nil if rest.include?("id: false")

      rest[/id:\s*:?["']?(\w+)/, 1] || "bigint"
    end

    def initialize(tables)
      @tables = tables
    end

    def table?(name)
      @tables.key?(name)
    end

    def column_type(table, column)
      @tables.dig(table, column)
    end
  end
end
