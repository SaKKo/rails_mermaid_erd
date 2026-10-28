# frozen_string_literal: true

require "prism"

module RailsMermaidErd
  Association = Struct.new(:macro, :name, :options, :owner, :file, :line, keyword_init: true) do
    def through?
      options.key?("through")
    end
  end

  ClassDef = Struct.new(:name, :superclass, :namespace, :file, :associations, :includes,
                        :abstract, :table_name, keyword_init: true)

  ConcernDef = Struct.new(:name, :associations, keyword_init: true)

  # Statically reads model files with Prism. Nothing is required or evaluated,
  # so the app (and its database) never has to boot.
  class Parser
    ASSOCIATION_MACROS = %i[belongs_to has_many has_one has_and_belongs_to_many].freeze
    UNKNOWN = :__unknown__

    attr_reader :classes, :concerns, :warnings

    def initialize
      @classes = {}
      @concerns = {}
      @warnings = []
    end

    def parse_files(paths)
      paths.each { |path| parse_file(path) }
      self
    end

    def parse_file(path)
      result = Prism.parse_file(path)
      unless result.errors.empty?
        @warnings << "#{path}: could not be parsed (#{result.errors.first.message})"
        return
      end
      @file = path
      visit(result.value, [], nil, {})
    end

    private

    # ns    - lexical namespace, e.g. ["Admin"]
    # owner - ClassDef or ConcernDef that associations belong to
    # extra - options merged in from an enclosing `with_options` block
    def visit(node, ns, owner, extra)
      case node
      when Prism::ClassNode
        visit_class(node, ns)
      when Prism::ModuleNode
        visit_module(node, ns)
      when Prism::SingletonClassNode, Prism::DefNode
        nil # associations are declared at class-body level only
      when Prism::CallNode
        visit_call(node, ns, owner, extra)
      else
        node&.compact_child_nodes&.each { |child| visit(child, ns, owner, extra) }
      end
    end

    def visit_class(node, ns)
      local = const_name(node.constant_path)
      full = qualify(local, ns)
      klass = (@classes[full] ||= ClassDef.new(name: full, namespace: full.split("::")[0..-2],
                                               file: @file, associations: [], includes: [],
                                               abstract: false))
      klass.superclass ||= node.superclass && const_name(node.superclass)
      visit(node.body, full.split("::"), klass, {}) if node.body
    end

    def visit_module(node, ns)
      full = qualify(const_name(node.constant_path), ns)
      concern = (@concerns[full] ||= ConcernDef.new(name: full, associations: []))
      visit(node.body, full.split("::"), concern, {}) if node.body
    end

    def visit_call(node, ns, owner, extra)
      name = node.name

      if ASSOCIATION_MACROS.include?(name) && owner && association_receiver?(node, extra)
        assoc = build_association(node, owner, extra)
        owner.associations << assoc if assoc
        return
      end

      if owner.is_a?(ConcernDef) && name == :included && node.receiver.nil? && node.block
        visit(node.block, ns, owner, extra) # ActiveSupport::Concern `included do ... end`
        return
      end

      if name == :with_options && node.block
        merged = extra.merge(keyword_options(node))
        merged[:__receivers__] = Array(extra[:__receivers__]) + block_params(node.block)
        visit(node.block.body, ns, owner, merged) if node.block.respond_to?(:body)
        return
      end

      if owner.is_a?(ClassDef) && node.receiver.nil?
        args(node).each { |a| (n = const_name(a)) && owner.includes << n } if name == :include
      end

      if owner.is_a?(ClassDef) && name == :table_name= && node.receiver.is_a?(Prism::SelfNode)
        value = literal(args(node).first)
        owner.table_name = value if value.is_a?(String)
      end

      # Rails 7+ ApplicationRecord uses `primary_abstract_class` instead of `self.abstract_class = true`
      owner.abstract = true if owner.is_a?(ClassDef) && name == :primary_abstract_class && node.receiver.nil?

      if owner.is_a?(ClassDef) && name == :abstract_class= && node.receiver.is_a?(Prism::SelfNode)
        owner.abstract = args(node).first.is_a?(Prism::TrueNode)
      end

      node.compact_child_nodes.each { |child| visit(child, ns, owner, extra) }
    end

    def association_receiver?(node, extra)
      return true if node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)

      # `with_options(...) do |assoc| assoc.has_many :x end`
      node.receiver.is_a?(Prism::LocalVariableReadNode) &&
        Array(extra[:__receivers__]).include?(node.receiver.name)
    end

    def build_association(node, owner, extra)
      first = args(node).first
      return nil unless first.is_a?(Prism::SymbolNode) || first.is_a?(Prism::StringNode)

      options = extra.reject { |k, _| k.is_a?(Symbol) }.merge(keyword_options(node))
      Association.new(macro: node.name, name: first.unescaped, options: options,
                      owner: owner.name, file: @file, line: node.location.start_line)
    end

    def keyword_options(node)
      hash = args(node).find { |a| a.is_a?(Prism::KeywordHashNode) || a.is_a?(Prism::HashNode) }
      return {} unless hash

      hash.elements.each_with_object({}) do |el, out|
        next unless el.is_a?(Prism::AssocNode) && el.key.respond_to?(:unescaped)

        out[el.key.unescaped] = literal(el.value)
      end
    end

    def literal(node)
      case node
      when Prism::SymbolNode, Prism::StringNode then node.unescaped
      when Prism::TrueNode then true
      when Prism::FalseNode then false
      when Prism::NilNode then nil
      when Prism::ConstantReadNode, Prism::ConstantPathNode then const_name(node)
      when Prism::ArrayNode
        values = node.elements.map { |e| literal(e) }
        values.include?(UNKNOWN) ? UNKNOWN : values
      when Prism::CallNode
        # `class_name: User.name` / `User.to_s`
        if %i[name to_s].include?(node.name) && node.receiver && (c = const_name(node.receiver))
          c.delete_prefix("::")
        else
          UNKNOWN
        end
      else
        UNKNOWN
      end
    end

    def args(node)
      node.arguments ? node.arguments.arguments : []
    end

    def block_params(block)
      params = block.respond_to?(:parameters) && block.parameters
      params = params.parameters if params.respond_to?(:parameters) && !params.is_a?(Prism::ParametersNode)
      return [] unless params.is_a?(Prism::ParametersNode)

      params.requireds.filter_map { |p| p.respond_to?(:name) ? p.name : nil }
    end

    # Returns "A::B", or "::A::B" for an explicitly top-level constant.
    def const_name(node)
      case node
      when Prism::ConstantReadNode
        node.name.to_s
      when Prism::ConstantPathNode
        child = node.respond_to?(:name) ? node.name.to_s : node.child.name.to_s
        return "::#{child}" if node.parent.nil?

        parent = const_name(node.parent)
        parent && "#{parent}::#{child}"
      end
    end

    def qualify(local, ns)
      return local.delete_prefix("::") if local.start_with?("::")

      (ns + [local]).join("::")
    end
  end
end
