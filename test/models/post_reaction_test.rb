require "test_helper"

class PostReactionTest < ActiveSupport::TestCase
  test "enforces one reaction per user per post" do
    post_record = posts(:one)
    user = users(:one)

    PostReaction.create!(post: post_record, user: user, kind: :like)
    duplicate = PostReaction.new(post: post_record, user: user, kind: :dislike)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "updates post counters when reaction changes" do
    post_record = posts(:one)
    user = users(:one)
    reaction = PostReaction.create!(post: post_record, user: user, kind: :like)

    assert_equal 1, post_record.reload.likes_count
    assert_equal 0, post_record.reload.dislikes_count

    reaction.update!(kind: :dislike)
    assert_equal 0, post_record.reload.likes_count
    assert_equal 1, post_record.reload.dislikes_count
  end
end
