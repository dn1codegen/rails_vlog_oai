require "test_helper"

class CommentTest < ActiveSupport::TestCase
  test "requires user and body" do
    comment = Comment.new(post: posts(:one), body: "")

    assert_not comment.valid?
    assert_includes comment.errors[:user], "can't be blank"
    assert_includes comment.errors[:body], "can't be blank"
  end

  test "sets author name from user email" do
    comment = Comment.new(post: posts(:one), user: users(:one), body: "Тест")

    assert comment.valid?
    assert_equal users(:one).email, comment.author_name
  end
end
