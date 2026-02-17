require "open3"

class Post < ApplicationRecord
  MODERN_VIDEO_CONTENT_TYPES = %w[
    video/mp4
    video/webm
    video/quicktime
    video/x-matroska
  ].freeze
  MODERN_VIDEO_CODECS = %w[av1 hevc h264 vp9].freeze

  has_one_attached :video
  has_one_attached :thumbnail
  has_many_attached :preview_frames
  belongs_to :user
  has_many :comments, dependent: :destroy
  has_many :post_reactions, dependent: :destroy

  validates :user, presence: true
  validates :title, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 5000 }

  before_validation :assign_title_from_video, on: :create
  validate :video_presence
  validate :video_content_type_supported
  validate :video_codec_supported
  after_commit :request_thumbnail_generation, on: :create

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
