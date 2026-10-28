class User < ApplicationRecord
  include Taggable

  has_many :posts, dependent: :destroy
  has_many :published_posts, -> { where(published: true) }, class_name: "Post"
  has_many :articles, class_name: "Post", foreign_key: :author_id, inverse_of: :author
  has_one :profile
  has_many :comments, as: :commentable
  has_many :liked_posts, through: :likes, source: :post   # ignored: through
  has_many :likes
  has_and_belongs_to_many :roles
  belongs_to :company, optional: true
end
