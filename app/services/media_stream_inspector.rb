require "json"
require "open3"

class MediaStreamInspector
  Result = Struct.new(
    :status,
    :video_codec,
    :audio_codec,
    :video_resolution,
    :video_bitrate,
    :audio_bitrate,
    :format_name,
    :message,
    keyword_init: true
  )

  class << self
    attr_accessor :forced_result
  end

  def self.inspect(blob)
    return forced_result if forced_result
    return Result.new(status: :no_blob) unless blob

    ffprobe_path = VideoCodecInspector.ffprobe
    return Result.new(status: :unavailable, message: "ffprobe not found") unless ffprobe_path

    result = nil
    blob.open do |video_file|
      file_path = video_file.path.to_s
      stdout, stderr, status = Open3.capture3(
        ffprobe_path,
        "-v", "error",
        "-show_streams",
        "-show_format",
        "-of", "json",
        file_path
      )

      return Result.new(status: :error, message: stderr.to_s.strip) unless status.success?

      payload = JSON.parse(stdout)
      streams = payload.fetch("streams", [])
      format_info = payload.fetch("format", {})
      video_stream = streams.find { |stream| stream["codec_type"] == "video" }
      audio_stream = streams.find { |stream| stream["codec_type"] == "audio" }
      video_width = video_stream&.fetch("width", nil).to_i
      video_height = video_stream&.fetch("height", nil).to_i
      video_resolution = if video_width.positive? && video_height.positive?
        "#{video_width}x#{video_height}"
      end

      result = Result.new(
        status: :ok,
        video_codec: video_stream&.fetch("codec_name", nil),
        audio_codec: audio_stream&.fetch("codec_name", nil),
        video_resolution: video_resolution,
        video_bitrate: parse_bitrate(video_stream&.fetch("bit_rate", nil)) || parse_bitrate(format_info["bit_rate"]),
        audio_bitrate: detect_audio_bitrate(
          audio_stream: audio_stream,
          format_info: format_info,
          ffprobe_path: ffprobe_path,
          file_path: file_path
        ),
        format_name: format_info["format_name"]
      )
    end

    result
  rescue JSON::ParserError => e
    Result.new(status: :error, message: e.message)
  rescue StandardError => e
    Result.new(status: :error, message: e.message)
  end

  def self.parse_bitrate(raw_value)
    value = raw_value.to_i
    value.positive? ? value : nil
  end

  def self.detect_audio_bitrate(audio_stream:, format_info:, ffprobe_path:, file_path:)
    return nil unless audio_stream

    parse_bitrate(audio_stream["bit_rate"]) ||
      parse_bitrate(audio_stream.dig("tags", "BPS")) ||
      parse_bitrate(audio_stream.dig("tags", "BPS-eng")) ||
      bitrate_from_pcm_stream(audio_stream) ||
      estimate_audio_bitrate_from_packets(
        ffprobe_path: ffprobe_path,
        file_path: file_path,
        audio_stream: audio_stream,
        format_info: format_info
      )
  end

  def self.bitrate_from_pcm_stream(audio_stream)
    codec_name = audio_stream["codec_name"].to_s
    return nil unless codec_name.start_with?("pcm_")

    sample_rate = audio_stream["sample_rate"].to_i
    channels = audio_stream["channels"].to_i
    bits_per_sample = audio_stream["bits_per_raw_sample"].to_i
    bits_per_sample = audio_stream["bits_per_sample"].to_i unless bits_per_sample.positive?
    return nil unless sample_rate.positive? && channels.positive? && bits_per_sample.positive?

    sample_rate * channels * bits_per_sample
  end

  def self.estimate_audio_bitrate_from_packets(ffprobe_path:, file_path:, audio_stream:, format_info:)
    duration = audio_duration_seconds(audio_stream, format_info)
    return nil unless duration&.positive?

    total_bytes = 0
    Open3.popen3(
      ffprobe_path,
      "-v", "error",
      "-select_streams", "a:0",
      "-show_entries", "packet=size",
      "-of", "csv=p=0",
      file_path
    ) do |_stdin, stdout, _stderr, wait_thr|
      stdout.each_line do |line|
        packet_size = line.to_i
        total_bytes += packet_size if packet_size.positive?
      end

      return nil unless wait_thr.value.success?
    end
    return nil unless total_bytes.positive?

    ((total_bytes * 8) / duration).round
  rescue StandardError
    nil
  end

  def self.audio_duration_seconds(audio_stream, format_info)
    parse_duration_seconds(audio_stream["duration"]) ||
      parse_duration_seconds(audio_stream.dig("tags", "DURATION")) ||
      parse_duration_seconds(audio_stream.dig("tags", "DURATION-eng")) ||
      parse_duration_seconds(format_info["duration"])
  end

  def self.parse_duration_seconds(raw_value)
    value = raw_value.to_s.strip
    return nil if value.empty?

    if value.include?(":")
      hours, minutes, seconds = value.split(":")
      return nil unless hours && minutes && seconds

      (hours.to_f * 3600) + (minutes.to_f * 60) + seconds.to_f
    else
      numeric = value.to_f
      numeric.positive? ? numeric : nil
    end
  end
end
