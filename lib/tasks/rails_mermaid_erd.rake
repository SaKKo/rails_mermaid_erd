Resolving dependencies...
# frozen_string_literal: true

namespace :erd do
  desc "Generate a Mermaid ER diagram of the app's models. " \
       "Options: OUTPUT=erd.mmd EXCLUDE=A,B FK_MODE=explicit " \
       "POLYMORPHIC='updated_by=User;Notification.created_by=User,Admin' POLYMORPHIC_FROM_DB=1"
  task mermaid: :environment do # :environment so custom inflections (and the DB lookup) work
    output = ENV.fetch("OUTPUT", Rails.root.join("erd.mmd").to_s)

    # Reads the distinct values of each unmapped polymorphic *_type column.
    lookup = if ENV["POLYMORPHIC_FROM_DB"].present?
        lambda do |model_name, assoc_name, _fk|
          model = model_name.safe_constantize or next []
          type_col = model.reflect_on_association(assoc_name.to_sym)&.foreign_type || "#{assoc_name}_type"
          model.unscoped.where.not(type_col => nil).distinct.pluck(type_col)
        rescue StandardError => e
          warn "rails_mermaid_erd: could not read #{model_name}.#{type_col} (#{e.class}: #{e.message})"
          []
        end
      end

    result = RailsMermaidErd.write(
      output,
      root: Rails.root.to_s,
      exclude: ENV.fetch("EXCLUDE", "").split(",").map(&:strip).reject(&:empty?),
      fk_mode: ENV["FK_MODE"] == "explicit" ? :explicit : :non_conventional,
      polymorphic: RailsMermaidErd.parse_polymorphic(ENV["POLYMORPHIC"]),
      polymorphic_lookup: lookup,
    )
    result.warnings.each { |w| warn "rails_mermaid_erd: #{w}" }
    puts "Wrote #{output} (#{result.models} models, #{result.relationships} relationships)"
  end
end
