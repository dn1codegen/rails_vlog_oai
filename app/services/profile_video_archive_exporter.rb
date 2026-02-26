require "json"
require "zip"

class ProfileVideoArchiveExporter
  Result = Struct.new(:status, :filename, :content_type, :data, :posts_count, :message, keyword_init: true)

  ARCHIVE_CONTENT_TYPE = "application/zip".freeze
  MANIFEST_FILENAME = "posts.json".freeze
  ARCHIVE_FORMAT = "vlog_posts_archive".freeze
  ARCHIVE_VERSION = 1

  def self.call(user:, posts: nil)
    source_posts = posts || user.posts
    exported_posts = []
    archive_data = Zip::OutputStream.write_buffer do |zip_stream|
      source_posts
        .includes(video_attachment: :blob)
        .order(created_at: :asc)
        .each do |post|
        next unless post.video.attached?

        video_path = archive_video_path(post:, index: exported_posts.size + 1)
        zip_stream.put_next_entry(video_path)
        post.video.blob.download { |chunk| zip_stream.write(chunk) }

        exported_posts << post_manifest_payload(post:, video_path:)
      end

      zip_stream.put_next_entry(MANIFEST_FILENAME)
      zip_stream.write(JSON.pretty_generate(manifest_payload(user:, posts: exported_posts)))
    end.string

    Result.new(
      status: :ok,
      filename: archive_filename,
      content_type: ARCHIVE_CONTENT_TYPE,
      data: archive_data,
      posts_count: exported_posts.size
    )
  rescue StandardError => e
    Result.new(status: :error, message: e.message, posts_count: 0)
  end

  def self.manifest_payload(user:, posts:)
    {
      format: ARCHIVE_FORMAT,
      version: ARCHIVE_VERSION,
      exported_at: Time.current.iso8601,
      user: {
        email: user.email,
        name: user.name
      },
      posts:
    }
  end
  private_class_method :manifest_payload

  def self.post_manifest_payload(post:, video_path:)
    {
      title: post.title,
      description: post.description,
      tags: post.tags,
      visibility: post.visibility,
      created_at: post.created_at&.iso8601,
      original_filename: post.video.filename.to_s,
      content_type: post.video.blob.content_type,
      byte_size: post.video.blob.byte_size,
      video_path:
    }
  end
  private_class_method :post_manifest_payload

  def self.archive_video_path(post:, index:)
    extension = post.video.filename.extension_with_delimiter.to_s
    extension = ".mp4" if extension.blank?

    basename = post.video.filename.base.to_s.parameterize
    basename = "video-#{post.id}" if basename.blank?

    "videos/%03d-%s%s" % [ index, basename, extension.downcase ]
  end
  private_class_method :archive_video_path

  def self.archive_filename
    "videos-archive-%s.zip" % Time.current.strftime("%Y%m%d-%H%M%S")
  end
  private_class_method :archive_filename
end
