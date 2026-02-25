require "test_helper"

class PostTest < ActiveSupport::TestCase
  setup do
    @video_path = Rails.root.join("test/fixtures/files/sample.mp4")
    @user = User.create!(email: "post-model-#{SecureRandom.hex(4)}@example.com", password: "Password123", password_confirmation: "Password123")
  end

  test "valid with supported container and codec" do
    post = Post.new(user: @user, title: "Travel vlog", description: "AV1 test")
    attach_sample_video(post)

    result = VideoCodecInspector::Result.new(status: :ok, codec: "av1")
    with_forced_result(result) do
      assert post.valid?
    end
  end

  test "invalid with unsupported container type" do
    post = Post.new(user: @user, title: "Legacy video")
    attach_sample_video(post, filename: "legacy.avi", content_type: "video/x-msvideo")

    result = VideoCodecInspector::Result.new(status: :ok, codec: "h264")
    with_forced_result(result) do
      assert_not post.valid?
      assert_includes post.errors[:video].join(" "), "контейнер"
    end
  end

  test "invalid with unsupported codec" do
    post = Post.new(user: @user, title: "Old codec")
    attach_sample_video(post)

    result = VideoCodecInspector::Result.new(status: :ok, codec: "mpeg2video")
    with_forced_result(result) do
      assert_not post.valid?
      assert_includes post.errors[:video].join(" "), "кодек"
    end
  end

  test "allows upload when codec cannot be read in non-strict mode" do
    post = Post.new(user: @user, title: "Codec parse failed")
    attach_sample_video(post)

    result = VideoCodecInspector::Result.new(status: :error, codec: nil)
    with_forced_result(result) do
      assert post.valid?
    end
  end

  test "normalizes tags and removes duplicates" do
    post = Post.new(
      user: @user,
      title: "Tagged post",
      tags: "  #Rails, API Design, rails,  qa & testing  "
    )
    attach_sample_video(post)

    result = VideoCodecInspector::Result.new(status: :ok, codec: "av1")
    with_forced_result(result) do
      assert post.valid?
    end

    assert_equal "rails, api-design, qa-testing", post.tags
    assert_equal %w[rails api-design qa-testing], post.tag_list
  end

  test "invalid when too many tags are provided" do
    post = Post.new(
      user: @user,
      title: "Too many tags",
      tags: (1..11).map { |index| "tag#{index}" }.join(", ")
    )
    attach_sample_video(post)

    result = VideoCodecInspector::Result.new(status: :ok, codec: "av1")
    with_forced_result(result) do
      assert_not post.valid?
    end

    assert_includes post.errors[:tags].join(" "), "не более 10"
  end

  private

  def attach_sample_video(post, filename: "sample.mp4", content_type: "video/mp4")
    File.open(@video_path) do |file|
      post.video.attach(io: file, filename:, content_type:)
    end
  end

  def with_forced_result(result)
    previous = VideoCodecInspector.forced_result
    VideoCodecInspector.forced_result = result
    yield
  ensure
    VideoCodecInspector.forced_result = previous
  end
end
