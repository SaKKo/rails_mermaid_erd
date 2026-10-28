class CreditRequest < ApplicationRecord
  belongs_to :actioned_by, polymorphic: true, optional: true
end
