require "json"
require "net/http"
require "stringio"
require "uri"

class PostTitleImageFinder
  Result = Struct.new(:status, :image_url, :message, keyword_init: true)
  API_HOST = "en.wikipedia.org".freeze
  IMAGE_HOSTS = %w[upload.wikimedia.org].freeze
  SEARCH_PATH = "/w/rest.php/v1/search/title".freeze

  class << self
    attr_accessor :forced_result
  end

  def self.attach_thumbnail(post)
    return evaluate_forced_result(post) if forced_result
    return Result.new(status: :up_to_date) if post.thumbnail.attached?
    return Result.new(status: :no_title) if post.title.blank?

    image_url = find_image_url(post.title)
    return Result.new(status: :not_found, message: "image not found") if image_url.blank?

    image_data, content_type = download_image(image_url)
    return Result.new(status: :download_failed, image_url:) unless image_data

    post.thumbnail.attach(
      io: StringIO.new(image_data),
      filename: "post-#{post.id}-fallback.jpg",
      content_type: content_type || "image/jpeg",
      metadata: { source: "title_search", source_url: image_url }
    )

    Result.new(status: :ok, image_url:)
  rescue StandardError => e
    Result.new(status: :error, message: e.message)
  end

  def self.find_image_url(title)
    uri = URI::HTTPS.build(
      host: API_HOST,
      path: SEARCH_PATH,
      query: URI.encode_www_form(q: title, limit: 5)
    )
    body = get_text_response(uri)
    return nil unless body

    data = JSON.parse(body)
    pages = data.fetch("pages", [])
    thumbnail_url = pages.lazy.map { |page| page.dig("thumbnail", "url") }.find(&:present?)
    normalize_image_url(thumbnail_url)
  rescue JSON::ParserError
    nil
  end

  def self.download_image(url)
    uri = URI.parse(url)
    return [ nil, nil ] unless IMAGE_HOSTS.include?(uri.host)

    response = get_response(uri)
    return [ nil, nil ] unless response.is_a?(Net::HTTPSuccess)

    content_type = response["content-type"]&.split(";")&.first
    return [ nil, nil ] unless content_type&.start_with?("image/")

    [ response.body, content_type ]
  end

  def self.get_text_response(uri)
    response = get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def self.get_response(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 4, open_timeout: 4) do |http|
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "VlogBot/1.0 (thumbnail fallback)"
      http.request(request)
    end
  end

  def self.normalize_image_url(url)
    return nil if url.blank?

    return "https:#{url}" if url.start_with?("//")

    url
  end

  def self.evaluate_forced_result(post)
    return forced_result.call(post) if forced_result.respond_to?(:call)

    forced_result
  end
end
