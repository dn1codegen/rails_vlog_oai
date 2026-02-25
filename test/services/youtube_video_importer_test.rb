require "test_helper"

class YoutubeVideoImporterTest < ActiveSupport::TestCase
  setup do
    @video_path = Rails.root.join("test/fixtures/files/sample.mp4")
    @user = User.create!(
      email: "youtube-importer-#{SecureRandom.hex(4)}@example.com",
      password: "Password123",
      password_confirmation: "Password123"
    )
  end

  test "download_and_attach keeps attachment valid for save after importer returns" do
    post = Post.new(user: @user, title: "Imported clip", description: "Downloaded from YouTube")

    with_fake_yt_dlp do |args_log_path|
      result = YoutubeVideoImporter.download_and_attach(
        post:,
        url: "https://www.youtube.com/watch?v=abc123",
        quality: "medium"
      )

      assert_equal :ok, result.status
      assert post.video.attached?
      assert_equal "YouTube title", result.title

      download_command = File.readlines(args_log_path, chomp: true).find { |line| line.include?("--output") }
      assert_includes download_command, "--limit-rate 2M"
      assert_includes download_command, "vcodec^=av01"
      assert_includes download_command, "acodec^=opus"
    end

    with_forced_codec_result(VideoCodecInspector::Result.new(status: :ok, codec: "av1")) do
      assert_difference("Post.count", 1) { post.save! }
    end
  end

  private

  def with_forced_codec_result(result)
    previous = VideoCodecInspector.forced_result
    VideoCodecInspector.forced_result = result
    yield
  ensure
    VideoCodecInspector.forced_result = previous
  end

  def with_fake_yt_dlp
    previous_path = ENV["YT_DLP_PATH"]
    previous_cache = if YoutubeVideoImporter.instance_variable_defined?(:@yt_dlp)
      YoutubeVideoImporter.instance_variable_get(:@yt_dlp)
    else
      :__missing__
    end

    Dir.mktmpdir("yt-dlp-test-") do |tmp_dir|
      script_path = File.join(tmp_dir, "yt-dlp")
      args_log_path = File.join(tmp_dir, "yt-dlp-args.log")
      script = <<~BASH
        #!/usr/bin/env bash
        set -euo pipefail
        echo "$*" >> "#{args_log_path}"

        if [[ "${1:-}" == "--version" ]]; then
          echo "2026.01.01"
          exit 0
        fi

        if [[ "${1:-}" == "--dump-single-json" ]]; then
          echo '{"title":"YouTube title","description":"YouTube description"}'
          exit 0
        fi

        output_template=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --output)
              output_template="$2"
              shift 2
              ;;
            *)
              shift
              ;;
          esac
        done

        if [[ -z "$output_template" ]]; then
          echo "missing --output argument" >&2
          exit 1
        fi

        cp "#{@video_path}" "${output_template//%(ext)s/mp4}"
      BASH

      File.write(script_path, script)
      File.chmod(0o755, script_path)
      ENV["YT_DLP_PATH"] = script_path
      YoutubeVideoImporter.remove_instance_variable(:@yt_dlp) if YoutubeVideoImporter.instance_variable_defined?(:@yt_dlp)

      yield args_log_path
    end
  ensure
    ENV["YT_DLP_PATH"] = previous_path
    if previous_cache == :__missing__
      YoutubeVideoImporter.remove_instance_variable(:@yt_dlp) if YoutubeVideoImporter.instance_variable_defined?(:@yt_dlp)
    else
      YoutubeVideoImporter.instance_variable_set(:@yt_dlp, previous_cache)
    end
  end
end
