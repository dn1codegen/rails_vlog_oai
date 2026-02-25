require "json"
require "open3"
require "tmpdir"
require "uri"

class YoutubeVideoImporter
  MetadataResult = Struct.new(:status, :title, :description, :message, keyword_init: true)
  DownloadResult = Struct.new(:status, :title, :description, :message, keyword_init: true)

  QUALITY_LEVELS = %w[high medium low].freeze
  QUALITY_FORMAT_SELECTORS = {
    "high" => "bestvideo*[vcodec^=av01][height<=1080]+bestaudio*[acodec^=opus]/bestvideo*[vcodec^=av01][height<=1080]+bestaudio/bestvideo*[height<=1080]+bestaudio*[acodec^=opus]/bestvideo*[height<=1080]+bestaudio/best[height<=1080]/best",
    "medium" => "bestvideo*[vcodec^=av01][height<=720]+bestaudio*[acodec^=opus]/bestvideo*[vcodec^=av01][height<=720]+bestaudio/bestvideo*[height<=720]+bestaudio*[acodec^=opus]/bestvideo*[height<=720]+bestaudio/best[height<=720]/best",
    "low" => "bestvideo*[vcodec^=av01][height<=360]+bestaudio*[acodec^=opus]/bestvideo*[vcodec^=av01][height<=360]+bestaudio/bestvideo*[height<=360]+bestaudio*[acodec^=opus]/bestvideo*[height<=360]+bestaudio/best[height<=360]/best"
  }.freeze
  DOWNLOAD_RATE_LIMIT = "2M".freeze
  SUPPORTED_EXTENSIONS = %w[mp4 webm mov mkv].freeze
  EXTENSION_CONTENT_TYPES = {
    "mp4" => "video/mp4",
    "webm" => "video/webm",
    "mov" => "video/quicktime",
    "mkv" => "video/x-matroska"
  }.freeze

  class << self
    attr_accessor :forced_metadata_result, :forced_download_result
  end

  def self.metadata(url)
    return evaluate_forced_metadata_result(url) if forced_metadata_result

    normalized_url = normalize_url(url)
    return MetadataResult.new(status: :invalid_url, message: "Укажите корректную ссылку на YouTube") unless normalized_url
    return MetadataResult.new(status: :unavailable, message: "yt-dlp не установлен на сервере") unless yt_dlp

    stdout, stderr, status = Open3.capture3(
      yt_dlp,
      "--dump-single-json",
      "--no-playlist",
      normalized_url
    )
    unless status.success?
      return MetadataResult.new(
        status: :error,
        message: stderr.to_s.strip.presence || "Не удалось получить данные YouTube"
      )
    end

    payload = JSON.parse(stdout)
    MetadataResult.new(
      status: :ok,
      title: payload["title"].to_s.strip,
      description: payload["description"].to_s.strip
    )
  rescue JSON::ParserError => e
    MetadataResult.new(status: :error, message: e.message)
  rescue StandardError => e
    MetadataResult.new(status: :error, message: e.message)
  end

  def self.download_and_attach(post:, url:, quality: nil)
    return evaluate_forced_download_result(post:, url:, quality:) if forced_download_result

    metadata_result = metadata(url)
    return DownloadResult.new(status: metadata_result.status, message: metadata_result.message) unless metadata_result.status == :ok

    selected_quality = normalize_quality(quality)
    return DownloadResult.new(status: :invalid_quality, message: "Выберите качество: high, medium или low") unless selected_quality

    return DownloadResult.new(status: :unavailable, message: "yt-dlp не установлен на сервере") unless yt_dlp

    normalized_url = normalize_url(url)
    return DownloadResult.new(status: :invalid_url, message: "Укажите корректную ссылку на YouTube") unless normalized_url

    format_selector = QUALITY_FORMAT_SELECTORS.fetch(selected_quality)

    Dir.mktmpdir("yt-dlp-import-") do |tmp_dir|
      output_template = File.join(tmp_dir, "video.%(ext)s")
      stdout, stderr, status = Open3.capture3(
        yt_dlp,
        "--no-playlist",
        "--format", format_selector,
        "--limit-rate", DOWNLOAD_RATE_LIMIT,
        "--output", output_template,
        normalized_url
      )
      unless status.success?
        return DownloadResult.new(
          status: :error,
          message: stderr.to_s.strip.presence || stdout.to_s.strip.presence || "Не удалось скачать видео"
        )
      end

      downloaded_path = Dir[File.join(tmp_dir, "video.*")].max_by { |path| File.mtime(path) }
      return DownloadResult.new(status: :error, message: "Не найден скачанный видеофайл") unless downloaded_path && File.size?(downloaded_path)

      extension = File.extname(downloaded_path).delete_prefix(".").downcase
      extension = "mp4" unless SUPPORTED_EXTENSIONS.include?(extension)
      content_type = EXTENSION_CONTENT_TYPES.fetch(extension, "application/octet-stream")

      File.open(downloaded_path, "rb") do |file|
        blob = ActiveStorage::Blob.create_and_upload!(
          io: file,
          filename: "youtube-#{selected_quality}.#{extension}",
          content_type:
        )
        post.video.attach(blob)
      end
    end

    DownloadResult.new(status: :ok, title: metadata_result.title, description: metadata_result.description)
  rescue StandardError => e
    DownloadResult.new(status: :error, message: e.message)
  end

  def self.yt_dlp
    return @yt_dlp if defined?(@yt_dlp)

    candidate = ENV["YT_DLP_PATH"].presence || "yt-dlp"
    _stdout, _stderr, status = Open3.capture3(candidate, "--version")
    @yt_dlp = status.success? ? candidate : nil
  rescue StandardError
    @yt_dlp = nil
  end

  def self.evaluate_forced_metadata_result(url)
    return forced_metadata_result.call(url) if forced_metadata_result.respond_to?(:call)

    forced_metadata_result
  end
  private_class_method :evaluate_forced_metadata_result

  def self.evaluate_forced_download_result(post:, url:, quality:)
    return forced_download_result.call(post:, url:, quality:) if forced_download_result.respond_to?(:call)

    forced_download_result
  end
  private_class_method :evaluate_forced_download_result

  def self.normalize_quality(raw_quality)
    quality = raw_quality.to_s.strip.downcase
    return "medium" if quality.blank?
    return quality if QUALITY_LEVELS.include?(quality)

    nil
  end
  private_class_method :normalize_quality

  def self.normalize_url(raw_url)
    url = raw_url.to_s.strip
    return nil if url.blank?

    uri = URI.parse(url)
    return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    return nil unless youtube_host?(uri.host)

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end
  private_class_method :normalize_url

  def self.youtube_host?(host)
    value = host.to_s.downcase
    value == "youtu.be" || value == "www.youtu.be" || value == "youtube.com" || value.end_with?(".youtube.com")
  end
  private_class_method :youtube_host?
end
