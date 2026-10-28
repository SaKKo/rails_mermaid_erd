class Notification < ApplicationRecord
  belongs_to :created_by, polymorphic: true
end
