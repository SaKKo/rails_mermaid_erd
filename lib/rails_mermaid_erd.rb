# frozen_string_literal: true

require "yaml"
require_relative "rails_mermaid_erd/version"
require_relative "rails_mermaid_erd/inflector"
require_relative "rails_mermaid_erd/parser"
require_relative "rails_mermaid_erd/schema"
require_relative "rails_mermaid_erd/graph"
require_relative "rails_mermaid_erd/renderer"
require_relative "rails_mermaid_erd/railtie" if defined?(Rails::Railtie)

# Reads Rails models (statically, without booting the app) and renders their
# associations as a Mermaid ER diagram.
module RailsMermaidErd
  Result = Struct.new(:mermaid, :warnings, :models, :relationships, keyword_init: true)

  # root        - Rails app root (default: current directory)
  # model_paths - dirs or files to scan (default: <root>/app/models)
  # schema_path - used only to type drawn foreign keys (default: <root>/db/schema.rb)
  # exclude     - model names to leave out, e.g. ["PaperTrail::Version"]
  # fk_mode     - :non_conventional (default) draws a foreign key whenever its column
  #               isn't <parent_model>_id; :explicit only when `foreign_key:` is set
  # polymorphic - targets for polymorphic belongs_to, merged over the config file:
  #               { "Notification.created_by" => ["User"], "updated_by" => ["User", "Admin"] }
  # polymorphic_lookup - callable(model, assoc, fk) => ["User", ...] for anything not mapped
  # config_path - YAML with `polymorphic:` / `exclude:` (default: <root>/config/rails_mermaid_erd.yml)
  def self.generate(root: Dir.pwd, model_paths: nil, schema_path: nil, exclude: [],
                    fk_mode: :non_conventional, polymorphic: {}, polymorphic_lookup: nil,
                    config_path: nil)
    config = load_config(config_path || File.join(root, "config", "rails_mermaid_erd.yml"))
    paths = model_paths || [File.join(root, "app", "models")]
    files = paths.flat_map do |p|
      File.file?(p) ? [p] : Dir.glob(File.join(p, "**", "*.rb"))
    end.sort.uniq

    parser = Parser.new.parse_files(files)
    schema = Schema.load(schema_path || File.join(root, "db", "schema.rb"))
    graph = Graph.new(parser, schema: schema, exclude: exclude + Array(config["exclude"]),
                              fk_mode: fk_mode,
                              polymorphic: (config["polymorphic"] || {}).merge(polymorphic),
                              polymorphic_lookup: polymorphic_lookup)

    Result.new(mermaid: Renderer.new(graph).render, warnings: graph.warnings,
               models: graph.models.size, relationships: graph.edges.size)
  end

  def self.load_config(path)
    return {} unless File.exist?(path)

    YAML.safe_load(File.read(path)) || {}
  end

  # "updated_by=User,Admin;Notification.created_by=User" => { "updated_by" => [...], ... }
  def self.parse_polymorphic(spec)
    spec.to_s.split(/[;\s]+/).each_with_object({}) do |pair, out|
      key, targets = pair.split("=", 2)
      out[key.strip] = targets.to_s.split(",").map(&:strip).reject(&:empty?) if key && !key.strip.empty?
    end
  end

  def self.write(output = "erd.mmd", **options)
    result = generate(**options)
    File.write(output, result.mermaid)
    result
  end
end
