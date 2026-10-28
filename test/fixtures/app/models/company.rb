class Company < ApplicationRecord
  has_many :users
  has_one :ceo, -> { where(ceo: true) }, class_name: "User"   # same FK as users
  has_many :employees, through: :users                        # ignored
end
