# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/rails_mermaid_erd"

class RailsMermaidErdTest < Minitest::Test
  ROOT = File.expand_path("fixtures", __dir__)

  def result(**opts)
    @result ||= {}
    @result[opts] ||= RailsMermaidErd.generate(root: ROOT, **opts)
  end

  def mermaid(**opts) = result(**opts).mermaid

  def test_starts_with_er_diagram
    assert mermaid.start_with?("erDiagram\n")
  end

  def test_merges_belongs_to_with_inverse_has_many
    assert_includes mermaid, %(User ||--o{ Post : "posts, published_posts")
    assert_equal 1, mermaid.scan(/User \|\|--o\{ Post : "posts/).size
  end

  def test_through_associations_are_ignored
    refute_match(/liked_posts|commenters|employees|"tags"/, mermaid)
  end

  def test_has_one_and_optional
    assert_includes mermaid, %(User ||--o| Profile : "profile")
    assert_includes mermaid, %(User |o--o{ Post : "articles")
    assert_includes mermaid, %(Company |o--o{ User : "users, ceo")
  end

  def test_habtm_drawn_once
    assert_equal 1, mermaid.scan("}o--o{").size
    assert_includes mermaid, %(Role }o--o{ User)
  end

  def test_with_options_and_concerns
    assert_includes mermaid, %(Post ||--o{ Like : "likes")
    assert_includes mermaid, %(User ||--o{ Tagging : "taggings")
  end

  def test_namespaces_resolve_and_are_quoted
    assert_includes mermaid, %("Admin::AuditLog" ||--o{ "Admin::Note" : "audit_log")
    assert_includes mermaid, %(User ||--o{ "Admin::AuditLog" : "user")
    assert(result.warnings.any? { |w| w.include?("Ghost") })
  end

  def test_only_non_conventional_fks_are_shown_with_schema_types
    post = mermaid[/    Post \{\n(.*?)\n    \}/m, 1]
    assert_includes post, "integer author_id FK"
    assert_includes post, "uuid editor_uuid FK"
    refute_includes post, "user_id"
    assert_includes mermaid, "uuid uuid PK"
    assert_includes mermaid, "integer manager_id FK"
    assert_includes mermaid, %(string commentable_type "polymorphic")
  end

  def test_no_attributes_for_conventional_models
    refute_match(/Profile \{|Like \{|Role \{/, mermaid)
  end

  def test_explicit_fk_mode
    out = mermaid(fk_mode: :explicit)
    refute_includes out, "reviewer_id"     # implied by belongs_to :reviewer
    assert_includes out, "editor_uuid FK"  # foreign_key: given
  end

  def test_isolated_and_sti_models_listed_abstract_and_plain_excluded
    assert_match(/^    Setting$/, mermaid)
    assert_match(/^    AdminUser$/, mermaid)
    refute_includes mermaid, "ApplicationRecord"
    refute_includes mermaid, "PlainRuby"
  end

  def test_exclude
    out = mermaid(exclude: ["Tag"])
    refute_match(/\bTag\b/, out)
    refute(result(exclude: ["Tag"]).warnings.any? { |w| w.include?("Tag ") })
  end
end

class PolymorphicTest < Minitest::Test
  ROOT = File.expand_path("fixtures", __dir__)
  CONFIG = File.join(ROOT, "config_polymorphic.yml")

  def test_unmapped_polymorphic_is_kept_as_attributes_with_hint
    r = RailsMermaidErd.generate(root: ROOT)
    assert_match(/    Branch \{\n        bigint updated_by_id FK\n        string updated_by_type "polymorphic"\n    \}/, r.mermaid)
    assert(r.warnings.any? { |w| w.include?("Branch.updated_by") && w.include?("polymorphic:") })
  end

  def test_config_file_maps_by_name_and_by_model
    out = RailsMermaidErd.generate(root: ROOT, config_path: CONFIG).mermaid
    assert_includes out, %(User |o--o{ Branch : "updated_by")
    assert_includes out, %(AdminUser |o--o{ Branch : "updated_by")
    assert_includes out, %(User ||--o{ Notification : "created_by")
  end

  def test_option_overrides_config_and_lookup_fills_the_rest
    calls = []
    lookup = ->(model, assoc, fk) { calls << [model, assoc, fk]; model == "CreditRequest" ? ["User", "Nope"] : [] }
    r = RailsMermaidErd.generate(root: ROOT, config_path: CONFIG, polymorphic_lookup: lookup,
                               polymorphic: RailsMermaidErd.parse_polymorphic("Notification.created_by=Company"))
    assert_includes r.mermaid, %(Company ||--o{ Notification : "created_by")
    refute_includes r.mermaid, %(User ||--o{ Notification)
    assert_includes r.mermaid, %(User |o--o{ CreditRequest : "actioned_by")
    assert_includes calls, ["CreditRequest", "actioned_by", "actioned_by_id"]
    refute(calls.any? { |c| c[0] == "Branch" })   # mapped by config, no lookup
    assert(r.warnings.any? { |w| w.include?("Nope not found") })
  end

  def test_as_counterpart_still_wins_without_config
    out = RailsMermaidErd.generate(root: ROOT).mermaid
    assert_includes out, %(Post ||--o{ Comment : "comments")
  end

  def test_parse_polymorphic
    assert_equal({ "updated_by" => %w[User Admin], "N.created_by" => ["User"] },
                 RailsMermaidErd.parse_polymorphic("updated_by=User,Admin; N.created_by=User"))
  end
end
