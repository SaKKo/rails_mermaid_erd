class Like < ApplicationRecord
  with_options optional: false do |assoc|
    assoc.belongs_to :user
    assoc.belongs_to :post
  end
end
