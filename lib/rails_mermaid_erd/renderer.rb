# frozen_string_literal: true

module RailsMermaidErd
  # Renders a Graph as a Mermaid `erDiagram`.
  #
  #   Parent ||--o{ Child : "has_many name"   (belongs_to required)
  #   Parent |o--o{ Child : "..."             (belongs_to optional: true)
  #   Parent ||--o| Child : "..."             (has_one)
  #   A      }o--o{ B     : "..."             (has_and_belongs_to_many)
  class Renderer
    def initialize(graph, indent: "    ")
      @graph = graph
      @indent = indent
    end

    def render
      lines = ["erDiagram"]
      connected = Set.new

      @graph.sorted_edges.each do |e|
        connected << e.parent << e.child
        lines << "#{@indent}#{entity(e.parent)} #{cardinality(e)} #{entity(e.child)} : #{quote(e.label)}"
      end

      @graph.models.keys.sort.each do |name|
        attrs = @graph.attributes[name]
        if attrs && !attrs.empty?
          lines << "#{@indent}#{entity(name)} {"
          attrs.each do |type, column, key, comment|
            parts = [type, column]
            parts << key if key
            parts << quote(comment) if comment
            lines << "#{@indent * 2}#{parts.join(' ')}"
          end
          lines << "#{@indent}}"
        elsif !connected.include?(name)
          lines << "#{@indent}#{entity(name)}"
        end
      end

      "#{lines.join("\n")}\n"
    end

    private

    def cardinality(edge)
      return "}o--o{" if edge.kind == :habtm

      left = edge.optional ? "|o" : "||"
      right = edge.kind == :one ? "o|" : "o{"
      "#{left}--#{right}"
    end

    # Namespaced models (Admin::User) need quoting to be valid Mermaid.
    def entity(name)
      name.match?(/\A[A-Za-z_][\w]*\z/) ? name : quote(name)
    end

    def quote(text)
      %("#{text.to_s.delete('"')}")
    end
  end
end
