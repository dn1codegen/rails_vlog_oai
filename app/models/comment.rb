class Comment < ApplicationRecord
  belongs_to :post

  validates :author_name, presence: true, length: { maximum: 80 }
  validates :body, presence: true, length: { maximum: 1000 }
end
