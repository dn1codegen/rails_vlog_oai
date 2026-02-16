require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes email and authenticates with password" do
    user = User.new(
      email: "  TeSt@Example.COM  ",
      password: "Password123",
      password_confirmation: "Password123"
    )

    assert user.save
    assert_equal "test@example.com", user.email
    assert user.authenticate("Password123")
    assert_not user.authenticate("wrong")
  end
end
