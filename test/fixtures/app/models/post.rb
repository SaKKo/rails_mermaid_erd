class Post < ApplicationRecord
  belongs_to :user
  belongs_to :author, class_name: "User", optional: true
  belongs_to :editor, class_name: User.name, foreign_key: "editor_uuid", primary_key: :uuid
  has_many :comments, as: :commentable
  has_many :commenters, through: :comments, source: :author  # ignored
  has_many :likes
end
