require "test_helper"

class PostTest < ActiveSupport::TestCase
  setup do
    @video_path = Rails.root.join("test/fixtures/files/sample.mp4")
    @cover_path = Rails.root.join("test/fixtures/files/cover.png")
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

  test "valid with supported audio container and codec" do
    post = Post.new(user: @user, title: "Audio release", tags: "Music")
    attach_sample_video(post, filename: "track.m4a", content_type: "audio/mp4")

    result = VideoCodecInspector::Result.new(status: :ok, codec: "aac")
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

  test "normalizes tags to allowed values and removes duplicates" do
    post = Post.new(
      user: @user,
      title: "Tagged post",
      tags: "  #film, MUSIC, audio-book, unknown, music  "
    )
    attach_sample_video(post)

    result = VideoCodecInspector::Result.new(status: :ok, codec: "av1")
    with_forced_result(result) do
      assert post.valid?
    end

    assert_equal "Film, Music, AudioBook", post.tags
    assert_equal %w[Film Music AudioBook], post.tag_list
  end

  test "accepts selected_tags array from form params" do
    post = Post.new(user: @user, title: "Selected tags")
    post.selected_tags = [ "Podcast", "Info", "podcast", "legacy-tag" ]
    attach_sample_video(post)

    result = VideoCodecInspector::Result.new(status: :ok, codec: "av1")
    with_forced_result(result) do
      assert post.valid?
    end

    assert_equal "Podcast, Info", post.tags
    assert_equal %w[Podcast Info], post.tag_list
  end

  test "list preview image prefers cover image and falls back to thumbnail" do
    post = Post.new(user: @user, title: "Preview priority")
    attach_sample_video(post)

    assert_nil post.list_preview_image

    post.thumbnail.attach(io: StringIO.new("thumb"), filename: "thumb.jpg", content_type: "image/jpeg")
    assert_equal post.thumbnail, post.list_preview_image

    File.open(@cover_path) do |file|
      post.cover_image.attach(io: file, filename: "cover.png", content_type: "image/png")
    end

    assert_equal post.cover_image, post.list_preview_image
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
