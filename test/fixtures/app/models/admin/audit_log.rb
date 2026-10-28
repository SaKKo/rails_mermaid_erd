module Admin
  class AuditLog < ApplicationRecord
    belongs_to :user                 # resolves to ::User
    belongs_to :reviewer, class_name: "::User"
  end
end
