# frozen_string_literal: true

module RailsMermaidErd
  # Thin wrapper around ActiveSupport::Inflector. Inside a Rails app the real
  # inflector (including the app's custom inflections) is always used; the
  # fallback only exists so the gem can run standalone.
  module Inflector
    begin
      require "active_support"
      require "active_support/inflector"
      ACTIVE_SUPPORT = true
    rescue LoadError
      ACTIVE_SUPPORT = false
    end

    IRREGULAR = {
      "person" => "people", "man" => "men", "woman" => "women", "child" => "children",
      "sex" => "sexes", "move" => "moves", "zombie" => "zombies", "ox" => "oxen"
    }.freeze
    UNCOUNTABLE = %w[equipment information rice money species series fish sheep jeans police].freeze

    module_function

    def classify(str)
      return ActiveSupport::Inflector.classify(str) if ACTIVE_SUPPORT

      str.to_s.split("/").map { |part| camelize(singularize(part)) }.join("::")
    end

    def singularize(word)
      return ActiveSupport::Inflector.singularize(word) if ACTIVE_SUPPORT

      w = word.to_s
      return w if UNCOUNTABLE.include?(w.downcase)

      irregular = IRREGULAR.key(w.downcase)
      return irregular if irregular

      case w
      when /(ss)$/i then w
      when /(quiz)zes$/i then w.sub(/zes$/i, "")
      when /(matr|vert|ind)ices$/i then w.sub(/ices$/i, "ix")
      when /([^aeiouy]|qu)ies$/i then w.sub(/ies$/i, "y")
      when /(x|ch|ss|sh|us|sis)es$/i then w.sub(/es$/i, "")
      when /(alias|status|bus)$/i then w
      when /([lr])ves$/i then w.sub(/ves$/i, "f")
      when /s$/i then w.chomp("s")
      else w
      end
    end

    def pluralize(word)
      return ActiveSupport::Inflector.pluralize(word) if ACTIVE_SUPPORT

      w = word.to_s
      return w if UNCOUNTABLE.include?(w.downcase)
      return IRREGULAR[w.downcase] if IRREGULAR.key?(w.downcase)

      case w
      when /(quiz)$/i then "#{w}zes"
      when /(matr|vert|ind)(ix|ex)$/i then w.sub(/(ix|ex)$/i, "ices")
      when /(x|ch|ss|sh|us)$/i then "#{w}es"
      when /([^aeiouy]|qu)y$/i then w.sub(/y$/i, "ies")
      when /s$/i then w
      else "#{w}s"
      end
    end

    def camelize(str)
      return ActiveSupport::Inflector.camelize(str) if ACTIVE_SUPPORT

      str.to_s.split("/").map { |p| p.split("_").map(&:capitalize).join }.join("::")
    end

    def underscore(str)
      return ActiveSupport::Inflector.underscore(str) if ACTIVE_SUPPORT

      str.to_s.gsub("::", "/")
         .gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
         .gsub(/([a-z\d])([A-Z])/, '\1_\2')
         .tr("-", "_").downcase
    end

    def demodulize(str)
      str.to_s.split("::").last
    end

    # Same rule as ActiveSupport's String#foreign_key: "Admin::User" => "user_id"
    def foreign_key(class_name)
      "#{underscore(demodulize(class_name))}_id"
    end

    def tableize(class_name)
      pluralize(underscore(class_name).tr("/", "_"))
    end
  end
end
