class Comment < ApplicationRecord
  belongs_to :post
  belongs_to :user, optional: true

  before_validation :assign_author_name_from_user

  validates :user, presence: true
  validates :author_name, presence: true, length: { maximum: 255 }
  validates :body, presence: true, length: { maximum: 1000 }

  private

  def assign_author_name_from_user
    return unless user

    self.author_name = user.email
  end
end
