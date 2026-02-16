require "open3"
require "stringio"
require "tempfile"

class VideoThumbnailGenerator
  Result = Struct.new(:status, :message, keyword_init: true)
  THUMBNAIL_SECOND = 30
  PREVIEW_PERCENTS = [ 10, 20, 30, 40, 50, 60, 70, 80 ].freeze

  class << self
    attr_accessor :forced_result

    def generate(post)
      return evaluate_forced_result(post) if forced_result
      return Result.new(status: :no_video) unless post.video.attached?
      return Result.new(status: :unavailable, message: "ffmpeg not found") unless ffmpeg
      return Result.new(status: :unavailable, message: "ffprobe not found") unless ffprobe
      return Result.new(status: :up_to_date) if up_to_date?(post)

      duration = probe_duration(post.video.blob)
      return Result.new(status: :error, message: "could not determine video duration") unless duration&.positive?

      frame_payloads, extract_errors = extract_preview_frames(post.video.blob, duration)
      if frame_payloads.empty?
        return Result.new(status: :error, message: extract_errors.join(" | ").presence || "frame extraction failed")
      end

      attach_preview_frames(post, frame_payloads)
      attach_thumbnail(post, frame_payloads)

      Result.new(status: :ok)
    rescue StandardError => e
      Result.new(status: :error, message: e.message)
    end

    def ffmpeg
      return @ffmpeg if defined?(@ffmpeg)

      candidate = ENV["FFMPEG_PATH"].presence || "ffmpeg"
      _stdout, _stderr, status = Open3.capture3(candidate, "-version")
      @ffmpeg = status.success? ? candidate : nil
    rescue StandardError
      @ffmpeg = nil
    end

    def ffprobe
      VideoCodecInspector.ffprobe
    end

    private

    def evaluate_forced_result(post)
      return forced_result.call(post) if forced_result.respond_to?(:call)

      forced_result
    end

    def probe_duration(blob)
      duration = nil
      blob.open do |video_file|
        stdout, _stderr, status = Open3.capture3(
          ffprobe,
          "-v", "error",
          "-show_entries", "format=duration",
          "-of", "default=nokey=1:noprint_wrappers=1",
          video_file.path.to_s
        )

        return nil unless status.success?

        duration = stdout.to_f
      end

      duration
    end

    def extract_preview_frames(blob, duration)
      payloads = {}
      errors = []

      blob.open do |video_file|
        PREVIEW_PERCENTS.each do |percent|
          second = second_for_percent(duration, percent)

          Tempfile.create([ "thumb-#{percent}-", ".jpg" ]) do |thumbnail_file|
            attempt = extract_frame(video_file.path.to_s, thumbnail_file.path.to_s, second)
            if attempt[:ok]
              payloads[percent] = File.binread(thumbnail_file.path.to_s)
            else
              errors << "percent=#{percent}: #{attempt[:message]}"
            end
          end
        end
      end

      [ payloads, errors ]
    end

    def second_for_percent(duration, percent)
      requested = duration * (percent / 100.0)
      max_seek = [ duration - 0.1, 0.0 ].max
      [ requested, max_seek ].min.round(3)
    end

    def extract_frame(input_path, output_path, seek_second)
      stdout, stderr, status = Open3.capture3(
        ffmpeg,
        "-y",
        "-ss", seek_second.to_s,
        "-i", input_path,
        "-vframes", "1",
        "-vf", "scale='min(1280,iw)':-2",
        "-q:v", "2",
        output_path
      )

      {
        ok: status.success? && File.size?(output_path),
        message: [ stdout, stderr ].compact.join("\n").strip
      }
    end

    def attach_preview_frames(post, frame_payloads)
      post.preview_frames.purge

      frame_payloads.sort_by { |percent, _payload| percent }.each do |percent, payload|
        post.preview_frames.attach(
          io: StringIO.new(payload),
          filename: "post-#{post.id}-preview-#{percent}.jpg",
          content_type: "image/jpeg",
          metadata: { video_blob_id: post.video.blob.id, percent: percent }
        )
      end
    end

    def attach_thumbnail(post, frame_payloads)
      selected_percent = frame_payloads.key?(THUMBNAIL_SECOND) ? THUMBNAIL_SECOND : frame_payloads.keys.min
      payload = frame_payloads.fetch(selected_percent)

      post.thumbnail.attach(
        io: StringIO.new(payload),
        filename: "post-#{post.id}-thumbnail.jpg",
        content_type: "image/jpeg",
        metadata: { video_blob_id: post.video.blob.id, percent: selected_percent, source: "video_frame" }
      )
    end

    def up_to_date?(post)
      return false unless post.thumbnail.attached?
      return false unless post.preview_frames.attached?
      return false unless post.thumbnail.blob.metadata["video_blob_id"] == post.video.blob.id

      percents = post.preview_frames_attachments.filter_map do |attachment|
        metadata = attachment.blob.metadata
        next unless metadata["video_blob_id"] == post.video.blob.id

        metadata["percent"]&.to_i
      end.sort

      percents == PREVIEW_PERCENTS
    end
  end
end
