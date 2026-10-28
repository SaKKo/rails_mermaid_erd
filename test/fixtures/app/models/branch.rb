class Branch < ApplicationRecord
  belongs_to :updated_by, polymorphic: true, optional: true
end
