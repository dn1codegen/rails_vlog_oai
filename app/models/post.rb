require "open3"

class Post < ApplicationRecord
  SUPPORTED_VIDEO_CONTENT_TYPES = %w[
    video/mp4
    video/webm
    video/quicktime
    video/x-matroska
  ].freeze
  SUPPORTED_AUDIO_CONTENT_TYPES = %w[
    audio/ogg
    audio/opus
    audio/mp4
    audio/x-m4a
    audio/x-m4b
    audio/flac
    audio/x-flac
    audio/alac
  ].freeze
  SUPPORTED_MEDIA_CONTENT_TYPES = (SUPPORTED_VIDEO_CONTENT_TYPES + SUPPORTED_AUDIO_CONTENT_TYPES).freeze
  SUPPORTED_VIDEO_CODECS = %w[av1 hevc h264 vp9].freeze
  SUPPORTED_AUDIO_CODECS = %w[opus flac alac aac].freeze
  ALLOWED_TAGS = %w[Film Music AudioBook Info Stream Podcast].freeze
  TAG_SPLIT_REGEX = /[,\n]/

  has_one_attached :video
  has_one_attached :thumbnail
  has_one_attached :cover_image
  has_many_attached :preview_frames
  belongs_to :user
  has_many :comments, dependent: :destroy
  has_many :post_reactions, dependent: :destroy

  attr_accessor :youtube_url, :youtube_quality
  attr_accessor :skip_video_codec_validation
  enum :visibility, { public_post: 0, private_post: 1 }, default: :public_post, prefix: :visibility

  validates :user, presence: true
  validates :title, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 5000 }
  validates :tags, length: { maximum: 500 }

  before_validation :assign_title_from_video, on: :create
  before_validation :normalize_tags
  validate :video_presence
  validate :video_content_type_supported, if: :video_requires_validation?
  validate :video_codec_supported, if: :video_codec_validation_required?
  after_commit :request_thumbnail_generation, on: :create
  scope :visible_to, ->(user) do
    if user.present?
      where("posts.visibility = :public_visibility OR posts.user_id = :user_id", public_visibility: visibilities.fetch("public_post"), user_id: user.id)
    else
      where(visibility: visibilities.fetch("public_post"))
    end
  end

  def tag_list
    normalize_tag_values(tags)
  end

  def selected_tags
    tag_list
  end

  def selected_tags=(values)
    self.tags = normalize_tag_values(values).join(", ")
  end

  def visible_to?(user)
    visibility_public_post? || user == self.user
  end

  def request_thumbnail_generation
    return unless video.attached?
    return unless video_media?

    if sync_thumbnail_generation?
      GeneratePostThumbnailJob.perform_now(self)
    else
      GeneratePostThumbnailJob.perform_later(self)
    end
  end

  def list_preview_image
    return cover_image if cover_image.attached?
    return thumbnail if thumbnail.attached?

    nil
  end

  def video_media?
    media_content_type.start_with?("video/")
  end

  def audio_media?
    media_content_type.start_with?("audio/")
  end

  def refresh_reaction_counters!
    likes = post_reactions.where(kind: PostReaction.kinds.fetch("like")).count
    dislikes = post_reactions.where(kind: PostReaction.kinds.fetch("dislike")).count

    update_columns(likes_count: likes, dislikes_count: dislikes)
  end

  private

  def normalize_tags
    self.tags = normalize_tag_values(tags).join(", ")
  end

  def normalize_tag_values(raw_tags)
    values = if raw_tags.is_a?(Array)
      raw_tags
    else
      raw_tags.to_s.split(TAG_SPLIT_REGEX)
    end

    values.filter_map { |tag| canonical_tag(tag) }.uniq
  end

  def canonical_tag(tag)
    normalized = tag.to_s
                    .strip
                    .delete_prefix("#")
                    .gsub(/[^\p{L}\p{N}]+/, "")
                    .downcase
    return if normalized.blank?

    ALLOWED_TAGS.find { |allowed_tag| allowed_tag.downcase == normalized }
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
    return if SUPPORTED_MEDIA_CONTENT_TYPES.include?(content_type)

    errors.add(:video, "контейнер #{content_type.inspect} не поддерживается. Разрешены видео и аудио-форматы")
  end

  def video_codec_supported
    return unless video.attached?

    inspection = VideoCodecInspector.inspect(video.blob)

    case inspection.status
    when :ok
      allowed_codecs = supported_codecs
      return if allowed_codecs.include?(inspection.codec)

      errors.add(:video, "кодек #{inspection.codec} не поддерживается. Разрешены: #{allowed_codecs.join(', ')}")
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

  def video_requires_validation?
    return false unless video.attached?

    new_record? || attachment_changes.key?("video")
  end

  def video_codec_validation_required?
    return false if skip_video_codec_validation

    video_requires_validation?
  end

  def media_content_type
    return "" unless video.attached?

    video.blob.content_type.to_s
  end

  def supported_codecs
    return SUPPORTED_AUDIO_CODECS if audio_media?
    return SUPPORTED_VIDEO_CODECS if video_media?

    (SUPPORTED_VIDEO_CODECS + SUPPORTED_AUDIO_CODECS).uniq
  end
end
