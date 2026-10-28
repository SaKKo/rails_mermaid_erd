# frozen_string_literal: true

require "set"

module RailsMermaidErd
  # One foreign-key link between two models. A `belongs_to` and its inverse
  # `has_many` / `has_one` describe the same link and are merged into one edge.
  class Edge
    attr_reader :parent, :child, :foreign_key, :kind, :polymorphic_as
    attr_accessor :optional, :explicit_fk, :primary_key, :has_side

    def initialize(parent:, child:, foreign_key:, kind:, polymorphic_as: nil)
      @parent = parent
      @child = child
      @foreign_key = foreign_key
      @kind = kind # :many, :one, :belongs_to (inverse unknown) or :habtm
      @polymorphic_as = polymorphic_as
      @has_names = []
      @belongs_names = []
      @optional = nil
      @explicit_fk = false
      @has_side = false
    end

    def add_has(name, kind)
      @has_names << name unless @has_names.include?(name)
      @has_side = true
      if kind == :many
        @kind = :many
      elsif kind == :one && @kind != :many
        @kind = :one
      end
    end

    def add_belongs(name)
      @belongs_names << name unless @belongs_names.include?(name)
    end

    def label
      names = @has_names.empty? ? @belongs_names : @has_names
      names.join(", ")
    end

    def foreign_keys
      Array(foreign_key)
    end
  end

  # Turns parsed classes into models and relationship edges.
  class Graph
    ROOTS = %w[ActiveRecord::Base ApplicationRecord].freeze

    attr_reader :models, :edges, :warnings, :attributes

    # polymorphic        - { "Model.assoc" or "assoc" => ["Target", ...] } for polymorphic
    #                      belongs_to whose targets can't be read from the code
    # polymorphic_lookup - optional callable(model_name, assoc_name, foreign_key) returning
    #                      target class names (the rake task uses it to read *_type from the DB)
    def initialize(parser, schema: Schema.new({}), exclude: [], fk_mode: :non_conventional,
                   polymorphic: {}, polymorphic_lookup: nil)
      @classes = parser.classes
      @concerns = parser.concerns
      @schema = schema
      @exclude = exclude.map { |n| n.delete_prefix("::") }.to_set
      @fk_mode = fk_mode
      @warnings = parser.warnings.dup
      @edges = {}
      @poly_belongs = {}
      @polymorphic = polymorphic.transform_keys(&:to_s).transform_values { |v| Array(v).map(&:to_s) }
      @polymorphic_lookup = polymorphic_lookup
      @unresolved_poly = []
      build
    end

    # attributes: { "Post" => [[type, column, key, comment], ...] }
    def build
      @models = @classes.values.select do |c|
        model?(c) && !c.abstract && !ROOTS.include?(c.name) && !@exclude.include?(c.name)
      end
      @models = @models.to_h { |c| [c.name, c] }
      @models.each_value do |klass|
        associations_for(klass).each { |assoc| add_association(klass, assoc) }
      end
      apply_polymorphic_belongs
      @edges.delete_if { |_, e| !@models.key?(e.parent) || !@models.key?(e.child) }
      @attributes = collect_attributes
    end

    def sorted_edges
      @edges.values.sort_by { |e| [e.parent, e.child, e.foreign_keys.join(","), e.label] }
    end

    private

    def model?(klass, seen = Set.new)
      return false if seen.include?(klass.name) || klass.superclass.nil?

      seen << klass.name
      sup = klass.superclass.delete_prefix("::")
      return true if sup == "ActiveRecord::Base"

      parent = resolve_in(@classes, klass.superclass, klass.namespace)
      return model?(parent, seen) if parent

      # ApplicationRecord (or another base) outside the scanned paths
      ROOTS.include?(sup) || sup.end_with?("Record")
    end

    def associations_for(klass)
      own = klass.associations
      from_concerns = klass.includes.flat_map do |mod|
        concern = resolve_in(@concerns, mod, klass.namespace)
        concern ? concern.associations : []
      end
      (own + from_concerns).reject(&:through?)
    end

    def add_association(klass, assoc)
      opts = assoc.options
      case assoc.macro
      when :belongs_to then add_belongs_to(klass, assoc, opts)
      when :has_many, :has_one then add_has(klass, assoc, opts)
      when :has_and_belongs_to_many then add_habtm(klass, assoc, opts)
      end
    end

    def add_belongs_to(klass, assoc, opts)
      fk = known(opts["foreign_key"]) || "#{assoc.name}_id"
      optional = opts["optional"] == true || opts["required"] == false

      if opts["polymorphic"]
        @poly_belongs[[klass.name, fk.to_s]] = { name: assoc.name, optional: optional,
                                                 explicit: opts.key?("foreign_key"),
                                                 type_column: known(opts["foreign_type"]) || "#{assoc.name}_type" }
        return
      end

      target = target_for(klass, assoc, opts) or return
      edge = edge(target, klass.name, fk, :belongs_to)
      edge.add_belongs(assoc.name)
      edge.optional = optional
      edge.explicit_fk ||= opts.key?("foreign_key")
      edge.primary_key ||= known(opts["primary_key"])
    end

    def add_has(klass, assoc, opts)
      target = target_for(klass, assoc, opts) or return
      as = known(opts["as"])
      fk = known(opts["foreign_key"]) || (as ? "#{as}_id" : Inflector.foreign_key(klass.name))
      edge = edge(klass.name, target, fk, :belongs_to, polymorphic_as: as)
      edge.add_has(assoc.name, assoc.macro == :has_one ? :one : :many)
      edge.explicit_fk ||= opts.key?("foreign_key")
      edge.primary_key ||= known(opts["primary_key"])
    end

    def add_habtm(klass, assoc, opts)
      target = target_for(klass, assoc, opts) or return
      a, b = [klass.name, target].sort
      key = [:habtm, a, b]
      @edges[key] ||= Edge.new(parent: a, child: b, foreign_key: nil, kind: :habtm)
      @edges[key].add_has(assoc.name, :habtm)
    end

    def apply_polymorphic_belongs
      @poly_belongs.each do |(child, fk), info|
        polymorphic_targets(child, info[:name], fk).each do |target|
          edge(target, child, fk, :belongs_to, polymorphic_as: info[:name]).add_belongs(info[:name])
        end

        matches = @edges.values.select { |e| e.polymorphic_as && e.child == child && e.foreign_keys == [fk] }
        if matches.empty?
          @unresolved_poly << [child, fk, info[:type_column]]
          @warnings << "#{child}.#{info[:name]}: polymorphic target unknown (no `as: :#{info[:name]}` " \
                       "in any model); drawn as attributes. Map it with " \
                       "polymorphic: { \"#{child}.#{info[:name]}\" => [\"User\"] } or \"#{info[:name]}\" => [...]"
        end
        matches.each do |e|
          e.optional = info[:optional]
          e.explicit_fk ||= info[:explicit]
        end
      end
    end

    # Targets from explicit config first ("Model.assoc", then "assoc"), else the lookup.
    def polymorphic_targets(child, name, fk)
      names = @polymorphic["#{child}.#{name}"] || @polymorphic[name]
      names ||= Array(@polymorphic_lookup&.call(child, name, fk)).map(&:to_s)
      names.uniq.filter_map do |target_name|
        target = resolve_in(@models, target_name, [])
        unless target || @exclude.include?(target_name.delete_prefix("::"))
          @warnings << "#{child}.#{name}: polymorphic target #{target_name} not found among the models"
        end
        target&.name
      end
    end

    def edge(parent, child, fk, kind, polymorphic_as: nil)
      key = [parent, child, Array(fk).map(&:to_s), polymorphic_as]
      @edges[key] ||= Edge.new(parent: parent, child: child, foreign_key: fk, kind: kind,
                               polymorphic_as: polymorphic_as)
    end

    def target_for(klass, assoc, opts)
      class_name = known(opts["class_name"])
      if opts.key?("class_name") && class_name.nil?
        @warnings << "#{klass.name}##{assoc.name}: class_name is not a literal, skipped (#{location(assoc)})"
        return nil
      end

      name = class_name || Inflector.classify(assoc.name)
      target = resolve_in(@models, name, klass.namespace)
      return target.name if target
      return nil if @exclude.include?(name.delete_prefix("::"))

      @warnings << "#{klass.name}##{assoc.name}: model #{name} not found, skipped (#{location(assoc)})"
      nil
    end

    # Rails-style constant lookup: Admin::Post looking for "User" tries
    # Admin::User, then User.
    def resolve_in(table, name, namespace)
      return table[name.delete_prefix("::")] if name.start_with?("::")

      namespace.length.downto(0) do |i|
        candidate = (namespace[0, i] + [name]).join("::")
        return table[candidate] if table.key?(candidate)
      end
      nil
    end

    def known(value)
      value == Parser::UNKNOWN ? nil : value
    end

    def location(assoc)
      "#{assoc.file}:#{assoc.line}"
    end

    # Only foreign keys that a reader could not infer from the model names
    # are drawn as attributes.
    def collect_attributes
      attrs = Hash.new { |h, k| h[k] = [] }
      @edges.each_value do |e|
        next if e.kind == :habtm

        show = if @fk_mode == :explicit
                 e.explicit_fk || e.polymorphic_as
               else
                 e.polymorphic_as || e.foreign_keys.map(&:to_s) != [Inflector.foreign_key(e.parent)]
               end

        if show
          e.foreign_keys.each do |fk|
            attrs[e.child] << [column_type(e.child, fk.to_s) || "bigint", fk.to_s, "FK", nil]
          end
          if e.polymorphic_as
            type_col = "#{e.polymorphic_as}_type"
            attrs[e.child] << [column_type(e.child, type_col) || "string", type_col, nil, "polymorphic"]
          end
        end

        pk = e.primary_key
        if pk && Array(pk).map(&:to_s) != ["id"]
          Array(pk).each { |c| attrs[e.parent] << [column_type(e.parent, c.to_s) || "bigint", c.to_s, "PK", nil] }
        end
      end
      @unresolved_poly.each do |child, fk, type_col|
        attrs[child] << [column_type(child, fk) || "bigint", fk, "FK", nil]
        attrs[child] << [column_type(child, type_col) || "string", type_col, nil, "polymorphic"]
      end
      attrs.transform_values { |list| list.uniq { |a| a[1] } }
    end

    def column_type(model_name, column)
      table = table_name(@models[model_name])
      table && @schema.column_type(table, column)
    end

    def table_name(klass, seen = Set.new)
      return nil if klass.nil? || seen.include?(klass.name)

      seen << klass.name
      return klass.table_name if klass.table_name

      # STI: subclasses share their parent's table
      parent = klass.superclass && resolve_in(@models, klass.superclass, klass.namespace)
      return table_name(parent, seen) if parent

      full = Inflector.tableize(klass.name)
      short = Inflector.tableize(Inflector.demodulize(klass.name))
      @schema.table?(full) ? full : short
    end
  end
end
