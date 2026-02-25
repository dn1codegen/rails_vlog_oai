require "open3"

class Post < ApplicationRecord
  MODERN_VIDEO_CONTENT_TYPES = %w[
    video/mp4
    video/webm
    video/quicktime
    video/x-matroska
  ].freeze
  MODERN_VIDEO_CODECS = %w[av1 hevc h264 vp9].freeze
  TAG_SPLIT_REGEX = /[,\n]/
  MAX_TAG_COUNT = 10
  MAX_TAG_LENGTH = 30

  has_one_attached :video
  has_one_attached :thumbnail
  has_many_attached :preview_frames
  belongs_to :user
  has_many :comments, dependent: :destroy
  has_many :post_reactions, dependent: :destroy

  validates :user, presence: true
  validates :title, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 5000 }
  validates :tags, length: { maximum: 500 }
  validate :tags_are_valid

  before_validation :assign_title_from_video, on: :create
  before_validation :normalize_tags
  validate :video_presence
  validate :video_content_type_supported
  validate :video_codec_supported
  after_commit :request_thumbnail_generation, on: :create

  def tag_list
    tags.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def request_thumbnail_generation
    return unless video.attached?

    if sync_thumbnail_generation?
      GeneratePostThumbnailJob.perform_now(self)
    else
      GeneratePostThumbnailJob.perform_later(self)
    end
  end

  def refresh_reaction_counters!
    likes = post_reactions.where(kind: PostReaction.kinds.fetch("like")).count
    dislikes = post_reactions.where(kind: PostReaction.kinds.fetch("dislike")).count

    update_columns(likes_count: likes, dislikes_count: dislikes)
  end

  private

  def normalize_tags
    normalized_tags = tags.to_s
                          .split(TAG_SPLIT_REGEX)
                          .map { |tag| normalize_tag(tag) }
                          .reject(&:blank?)
                          .uniq

    self.tags = normalized_tags.join(", ")
  end

  def normalize_tag(tag)
    tag.to_s
       .strip
       .delete_prefix("#")
       .downcase
       .gsub(/\s+/, "-")
       .gsub(/[^\p{L}\p{N}_-]/, "")
       .gsub(/-+/, "-")
       .gsub(/\A-|-+\z/, "")
  end

  def tags_are_valid
    current_tags = tag_list
    if current_tags.size > MAX_TAG_COUNT
      errors.add(:tags, "можно указать не более #{MAX_TAG_COUNT} тегов")
    end

    too_long_tag = current_tags.find { |tag| tag.length > MAX_TAG_LENGTH }
    return unless too_long_tag

    errors.add(:tags, "тег ##{too_long_tag} длиннее #{MAX_TAG_LENGTH} символов")
  end

  def assign_title_from_video
    return if title.present?
    return unless video.attached?

    generated_title = metadata_title_from_video || filename_title_from_video
    self.title = normalize_generated_title(generated_title)
  end

  def metadata_title_from_video
    ffprobe_path = VideoCodecInspector.ffprobe
    return nil unless ffprobe_path

    value = nil
    video.blob.open do |video_file|
      stdout, _stderr, status = Open3.capture3(
        ffprobe_path,
        "-v", "error",
        "-show_entries", "format_tags=title",
        "-of", "default=nokey=1:noprint_wrappers=1",
        video_file.path.to_s
      )

      next unless status.success?

      value = stdout.to_s.lines.map(&:strip).find(&:present?)
    end

    value
  rescue StandardError
    nil
  end

  def filename_title_from_video
    video.filename&.base&.to_s
  end

  def normalize_generated_title(raw_title)
    cleaned = raw_title.to_s.tr("_-", " ").squish
    return if cleaned.blank?

    cleaned[0, 120]
  end

  def video_presence
    return if video.attached?

    errors.add(:video, "нужно прикрепить")
  end

  def video_content_type_supported
    return unless video.attached?

    content_type = video.blob.content_type
    return if MODERN_VIDEO_CONTENT_TYPES.include?(content_type)

    errors.add(:video, "контейнер #{content_type.inspect} не поддерживается")
  end

  def video_codec_supported
    return unless video.attached?

    inspection = VideoCodecInspector.inspect(video.blob)

    case inspection.status
    when :ok
      return if MODERN_VIDEO_CODECS.include?(inspection.codec)

      errors.add(:video, "кодек #{inspection.codec} не поддерживается. Разрешены: #{MODERN_VIDEO_CODECS.join(', ')}")
    when :unavailable, :error, :empty
      return unless require_codec_verification?

      errors.add(:video, codec_inspection_error_message(inspection.status))
    else
      errors.add(:video, "не удалось прочитать кодек видео")
    end
  end

  def require_codec_verification?
    default = Rails.env.production? ? "true" : "false"
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("REQUIRE_FFPROBE", default))
  end

  def codec_inspection_error_message(status)
    return "сервер не может проверить кодек. Установите ffprobe (ffmpeg)" if status == :unavailable

    "не удалось прочитать кодек видео"
  end

  def sync_thumbnail_generation?
    default = Rails.env.development? ? "true" : "false"
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("THUMBNAIL_SYNC", default))
  end
end
