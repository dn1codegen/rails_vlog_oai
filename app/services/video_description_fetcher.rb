require "cgi"
require "json"
require "net/http"
require "open3"
require "uri"

class VideoDescriptionFetcher
  Result = Struct.new(
    :status,
    :description,
    :source,
    :query,
    :source_order,
    :message,
    keyword_init: true
  )
  Source = Struct.new(
    :name,
    :access_score,
    :freshness_score,
    :order_index,
    :fetcher,
    keyword_init: true
  )

  NOISE_TOKENS = %w[
    2160p 1080p 720p 480p 4k uhd hdr dvdrip bdrip bluray
    webdl webrip x264 x265 h264 h265 hevc av1 vp9 aac ac3 dts
  ].freeze

  class << self
    attr_accessor :forced_result
  end

  def self.fetch(uploaded_file:, title_hint: nil)
    return forced_result if forced_result

    query = extract_query(uploaded_file: uploaded_file, title_hint: title_hint)
    sources = prioritized_sources
    source_order = sources.map(&:name)

    return Result.new(
      status: :error,
      query: query,
      source_order: source_order,
      message: "Не удалось определить название видео для поиска."
    ) if query.blank?

    return Result.new(
      status: :error,
      query: query,
      source_order: source_order,
      message: "Нет доступных интернет-источников. Добавьте API-ключи или заполните описание вручную."
    ) if sources.empty?

    sources.each do |source|
      description = source.fetcher.call(query)
      next if description.blank?
      normalized_description = normalize_description(description)
      next if normalized_description.blank?

      return Result.new(
        status: :ok,
        description: normalized_description,
        source: source.name,
        query: query,
        source_order: source_order
      )
    rescue StandardError => e
      Rails.logger.info("VideoDescriptionFetcher #{source.name} error: #{e.class}: #{e.message}")
    end

    Result.new(
      status: :not_found,
      query: query,
      source_order: source_order,
      message: "Описание не найдено. Уточните название и попробуйте снова."
    )
  end

  def self.prioritized_sources
    sources = [
      Source.new(
        name: "Wikipedia",
        access_score: 5,
        freshness_score: 3,
        order_index: 1,
        fetcher: method(:fetch_from_wikipedia)
      )
    ]

    if ENV["YOUTUBE_API_KEY"].present?
      sources << Source.new(
        name: "YouTube Data API",
        access_score: 3,
        freshness_score: 5,
        order_index: 2,
        fetcher: method(:fetch_from_youtube)
      )
    end

    if ENV["TMDB_API_KEY"].present?
      sources << Source.new(
        name: "TMDB",
        access_score: 3,
        freshness_score: 5,
        order_index: 3,
        fetcher: method(:fetch_from_tmdb)
      )
    end

    sources.sort_by do |source|
      [ -source.access_score, -source.freshness_score, source.order_index ]
    end
  end

  def self.extract_query(uploaded_file:, title_hint:)
    candidates = [
      cleanup_query(title_hint),
      cleanup_query(metadata_title(uploaded_file)),
      cleanup_query(filename_title(uploaded_file))
    ]

    candidates.find(&:present?)
  end

  def self.filename_title(uploaded_file)
    return nil unless uploaded_file.respond_to?(:original_filename)

    File.basename(uploaded_file.original_filename.to_s, ".*")
  rescue StandardError
    nil
  end

  def self.metadata_title(uploaded_file)
    return nil unless uploaded_file.respond_to?(:tempfile)

    tempfile_path = uploaded_file.tempfile&.path.to_s
    return nil if tempfile_path.blank?

    ffprobe_path = VideoCodecInspector.ffprobe
    return nil unless ffprobe_path

    stdout, _stderr, status = Open3.capture3(
      ffprobe_path,
      "-v", "error",
      "-show_entries", "format_tags=title",
      "-of", "default=nokey=1:noprint_wrappers=1",
      tempfile_path
    )

    return nil unless status.success?

    stdout.to_s.lines.map(&:strip).find(&:present?)
  rescue StandardError
    nil
  end

  def self.cleanup_query(raw_query)
    value = raw_query.to_s
    return nil if value.blank?

    normalized = value.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
    normalized.tr!("._-", " ")
    NOISE_TOKENS.each do |token|
      normalized.gsub!(/\b#{Regexp.escape(token)}\b/i, " ")
    end
    normalized.gsub!(/[^\p{L}\p{N}\s]/u, " ")
    normalized.squish!
    normalized = normalized[0, 140]
    normalized.presence
  rescue StandardError
    nil
  end

  def self.fetch_from_wikipedia(query)
    %w[ru en].each do |language|
      title = wikipedia_title(query, language)
      next if title.blank?

      description = wikipedia_summary(title, language)
      return description if description.present?
    end

    nil
  end

  def self.wikipedia_title(query, language)
    search_url = "https://#{language}.wikipedia.org/w/api.php?" \
      "action=opensearch&format=json&limit=1&namespace=0&search=#{CGI.escape(query)}"
    payload = fetch_json(search_url)
    return nil unless payload.is_a?(Array)

    payload.dig(1, 0).to_s.strip.presence
  end

  def self.wikipedia_summary(title, language)
    encoded_title = CGI.escape(title).tr("+", "%20")
    summary_url = "https://#{language}.wikipedia.org/api/rest_v1/page/summary/#{encoded_title}"
    payload = fetch_json(summary_url)
    return nil unless payload.is_a?(Hash)
    return nil if payload["type"].to_s == "disambiguation"

    payload["extract"].to_s.strip.presence
  end

  def self.fetch_from_youtube(query)
    api_key = ENV["YOUTUBE_API_KEY"].to_s
    return nil if api_key.blank?

    search_url = "https://www.googleapis.com/youtube/v3/search?" \
      "part=snippet&type=video&maxResults=1&q=#{CGI.escape(query)}&key=#{CGI.escape(api_key)}"
    search_payload = fetch_json(search_url)
    video_id = search_payload.dig("items", 0, "id", "videoId").to_s
    return nil if video_id.blank?

    details_url = "https://www.googleapis.com/youtube/v3/videos?" \
      "part=snippet&id=#{CGI.escape(video_id)}&key=#{CGI.escape(api_key)}"
    details_payload = fetch_json(details_url)
    description = details_payload.dig("items", 0, "snippet", "description").to_s.strip
    description.presence
  end

  def self.fetch_from_tmdb(query)
    api_key = ENV["TMDB_API_KEY"].to_s
    return nil if api_key.blank?

    %w[ru-RU en-US].each do |language|
      search_url = "https://api.themoviedb.org/3/search/multi?" \
        "api_key=#{CGI.escape(api_key)}&language=#{CGI.escape(language)}&include_adult=false&page=1" \
        "&query=#{CGI.escape(query)}"

      payload = fetch_json(search_url)
      next unless payload.is_a?(Hash)

      overview = find_tmdb_overview(payload["results"])
      return overview if overview.present?
    end

    nil
  end

  def self.find_tmdb_overview(results)
    items = Array(results)

    preferred = items.find do |item|
      media_type = item["media_type"].to_s
      %w[movie tv].include?(media_type) && item["overview"].to_s.strip.present?
    end
    return preferred["overview"].to_s.strip if preferred

    fallback = items.find { |item| item["overview"].to_s.strip.present? }
    fallback&.dig("overview")&.to_s&.strip
  end

  def self.fetch_json(url)
    uri = URI.parse(url)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "VlogMetadataFetcher/1.0"

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: 4,
      read_timeout: 7
    ) do |http|
      http.request(request)
    end

    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError, StandardError
    nil
  end

  def self.normalize_description(description)
    value = description.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
    value.gsub!(/\r\n?/, "\n")
    value.gsub!(/[ \t]+/, " ")
    value.gsub!(/\n{3,}/, "\n\n")
    value.strip!
    value = value[0, 5000]
    value.presence
  rescue StandardError
    nil
  end
end
