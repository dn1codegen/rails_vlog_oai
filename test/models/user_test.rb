require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes email and profile fields and authenticates with password" do
    user = User.new(
      email: "  TeSt@Example.COM  ",
      name: "   Alex   Dev   ",
      bio: "   Люблю тестировать Rails.   ",
      password: "Password123",
      password_confirmation: "Password123"
    )

    assert user.save
    assert_equal "test@example.com", user.email
    assert_equal "Alex Dev", user.name
    assert_equal "Люблю тестировать Rails.", user.bio
    assert_equal "Alex Dev", user.display_name
    assert user.authenticate("Password123")
    assert_not user.authenticate("wrong")
  end

  test "falls back to email when name is blank" do
    user = User.new(
      email: "fallback@example.com",
      password: "Password123",
      password_confirmation: "Password123"
    )

    assert user.save
    assert_equal "fallback@example.com", user.display_name
  end

  test "validates profile field lengths" do
    user = User.new(
      email: "limits@example.com",
      name: "a" * (User::NAME_MAX_LENGTH + 1),
      bio: "b" * (User::BIO_MAX_LENGTH + 1),
      password: "Password123",
      password_confirmation: "Password123"
    )

    assert_not user.valid?
    assert user.errors.added?(:name, :too_long, count: User::NAME_MAX_LENGTH)
    assert user.errors.added?(:bio, :too_long, count: User::BIO_MAX_LENGTH)
  end
end
