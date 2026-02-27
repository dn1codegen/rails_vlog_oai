require "open3"

class VideoCodecInspector
  Result = Struct.new(:status, :codec, keyword_init: true)
  class << self
    attr_accessor :forced_result
  end

  def self.inspect(blob)
    return forced_result if forced_result
    return Result.new(status: :no_blob) unless blob

    ffprobe_path = ffprobe
    return Result.new(status: :unavailable) unless ffprobe_path

    codec_name = nil
    blob.open do |tempfile|
      codec_name = detect_codec(ffprobe_path:, file_path: tempfile.path.to_s, stream_selector: "v:0")
      codec_name = detect_codec(ffprobe_path:, file_path: tempfile.path.to_s, stream_selector: "a:0") if codec_name.blank?
    end

    return Result.new(status: :empty) if codec_name.nil? || codec_name.empty?

    Result.new(status: :ok, codec: codec_name.downcase)
  rescue StandardError
    Result.new(status: :error)
  end

  def self.detect_codec(ffprobe_path:, file_path:, stream_selector:)
    stdout, _stderr, status = Open3.capture3(
      ffprobe_path,
      "-v", "error",
      "-select_streams", stream_selector,
      "-show_entries", "stream=codec_name",
      "-of", "default=nokey=1:noprint_wrappers=1",
      file_path
    )
    return nil unless status.success?

    stdout.lines.first&.strip&.downcase
  end

  def self.ffprobe
    return @ffprobe if defined?(@ffprobe)

    candidate = ENV["FFPROBE_PATH"].presence || "ffprobe"
    _stdout, _stderr, status = Open3.capture3(candidate, "-version")
    @ffprobe = status.success? ? candidate : nil
  rescue StandardError
    @ffprobe = nil
  end
end
