# frozen_string_literal: true

require_relative "lib/rails_mermaid_erd/version"

Gem::Specification.new do |spec|
  spec.name = "rails_mermaid_erd"
  spec.version = RailsMermaidErd::VERSION
  spec.authors = ["Your Name"]
  spec.summary = "Generate a Mermaid ER diagram from your Rails model associations"
  spec.description = "Statically reads app/models (no app boot, no database) and writes a Mermaid " \
                     "erDiagram of belongs_to / has_many / has_one / HABTM relationships, " \
                     "skipping :through associations."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir["lib/**/*", "exe/*", "README.md", "LICENSE.txt"]
  spec.bindir = "exe"
  spec.executables = ["rails_mermaid_erd"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 6.1"
  spec.add_dependency "prism", ">= 0.19"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
