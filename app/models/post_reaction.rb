class PostReaction < ApplicationRecord
  belongs_to :post
  belongs_to :user

  enum :kind, { like: 1, dislike: -1 }

  validates :kind, presence: true
  validates :user_id, uniqueness: { scope: :post_id }

  after_commit :refresh_post_counters, on: %i[create update destroy]

  private

  def refresh_post_counters
    post_record = Post.find_by(id: post_id)
    return unless post_record

    post_record.refresh_reaction_counters!
  end
end
