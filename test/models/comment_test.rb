require "test_helper"

class CommentTest < ActiveSupport::TestCase
  test "requires author and body" do
    comment = Comment.new(post: posts(:one), author_name: "", body: "")

    assert_not comment.valid?
    assert_includes comment.errors[:author_name], "can't be blank"
    assert_includes comment.errors[:body], "can't be blank"
  end
end
