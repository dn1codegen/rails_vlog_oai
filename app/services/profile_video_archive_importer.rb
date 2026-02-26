require "json"
require "tempfile"
require "zip"

class ProfileVideoArchiveImporter
  Result = Struct.new(:status, :imported_count, :failed_count, :errors, :message, keyword_init: true)
  Manifest = Struct.new(:payload, :base_dir, keyword_init: true)

  MANIFEST_FILENAME = ProfileVideoArchiveExporter::MANIFEST_FILENAME
  ARCHIVE_FORMAT = ProfileVideoArchiveExporter::ARCHIVE_FORMAT

  def self.call(user:, archive:)
    return Result.new(status: :invalid_file, imported_count: 0, failed_count: 0, errors: [], message: "Выберите ZIP-архив для импорта") unless archive.respond_to?(:path)

    imported_count = 0
    failed_count = 0
    errors = []

    Zip::File.open(archive.path) do |zip_file|
      manifest = read_manifest(zip_file)
      unless manifest
        return Result.new(status: :invalid_archive, imported_count: 0, failed_count: 0, errors: [], message: "В архиве отсутствует файл #{MANIFEST_FILENAME}")
      end

      posts_payload = validate_manifest(manifest.payload)
      unless posts_payload
        return Result.new(status: :invalid_archive, imported_count: 0, failed_count: 0, errors: [], message: "Файл #{MANIFEST_FILENAME} имеет неверный формат")
      end

      posts_payload.each_with_index do |post_payload, index|
        import_result = import_post(user:, zip_file:, post_payload:, index:, manifest_base_dir: manifest.base_dir)
        if import_result[:ok]
          imported_count += 1
        else
          failed_count += 1
          errors << import_result[:error]
        end
      end
    end

    if imported_count.positive? || failed_count.zero?
      Result.new(status: :ok, imported_count:, failed_count:, errors:)
    else
      Result.new(status: :error, imported_count:, failed_count:, errors:, message: "Не удалось импортировать ни одного видео")
    end
  rescue Zip::Error, JSON::ParserError => e
    Result.new(status: :invalid_archive, imported_count: 0, failed_count: 0, errors: [ e.message ], message: "Не удалось прочитать ZIP-архив")
  rescue StandardError => e
    Result.new(status: :error, imported_count: 0, failed_count: 0, errors: [ e.message ], message: "Ошибка импорта архива")
  end

  def self.read_manifest(zip_file)
    manifest_entry = zip_file.find_entry(MANIFEST_FILENAME)
    manifest_entry ||= zip_file.entries.find do |entry|
      next if entry.directory?

      File.basename(entry.name.to_s) == MANIFEST_FILENAME
    end
    return unless manifest_entry

    Manifest.new(
      payload: JSON.parse(manifest_entry.get_input_stream.read),
      base_dir: File.dirname(manifest_entry.name.to_s)
    )
  end
  private_class_method :read_manifest

  def self.validate_manifest(manifest)
    return unless manifest.is_a?(Hash)
    format = manifest["format"].to_s
    return unless format.blank? || format == ARCHIVE_FORMAT

    posts_payload = manifest["posts"]
    return posts_payload if posts_payload.is_a?(Array)

    nil
  end
  private_class_method :validate_manifest

  def self.import_post(user:, zip_file:, post_payload:, index:, manifest_base_dir:)
    return { ok: false, error: "Пост ##{index + 1}: неверный JSON-объект" } unless post_payload.is_a?(Hash)

    video_path = post_payload["video_path"].to_s
    return { ok: false, error: "Пост ##{index + 1}: отсутствует путь к видео" } if video_path.blank?

    video_entry = find_video_entry(zip_file:, video_path:, manifest_base_dir:)
    return { ok: false, error: "Пост ##{index + 1}: файл #{video_path} не найден в архиве" } unless video_entry

    post = user.posts.new(
      title: post_payload["title"],
      description: post_payload["description"],
      tags: post_payload["tags"],
      visibility: normalize_visibility(post_payload["visibility"])
    )
    post.skip_video_codec_validation = true

    filename = post_payload["original_filename"].to_s.strip
    filename = File.basename(video_path) if filename.blank?

    content_type = post_payload["content_type"].to_s.strip
    content_type = Marcel::MimeType.for(name: filename) if content_type.blank?

    saved = Tempfile.create([ "profile-import-", File.extname(filename) ]) do |tempfile|
      tempfile.binmode
      video_entry.get_input_stream { |input| IO.copy_stream(input, tempfile) }
      tempfile.rewind

      post.video.attach(io: tempfile, filename:, content_type:)
      post.save
    end

    return { ok: true } if saved

    error_title = post.title.presence || "без названия"
    { ok: false, error: "Пост #{error_title.inspect}: #{post.errors.full_messages.to_sentence}" }
  rescue StandardError => e
    { ok: false, error: "Пост ##{index + 1}: #{e.message}" }
  end
  private_class_method :import_post

  def self.find_video_entry(zip_file:, video_path:, manifest_base_dir:)
    normalized_path = video_path.to_s.tr("\\", "/").sub(%r{\A\./+}, "")
    return if normalized_path.blank?

    direct_entry = zip_file.find_entry(normalized_path)
    return direct_entry if direct_entry

    return if manifest_base_dir.blank? || manifest_base_dir == "."

    relative_path = File.join(manifest_base_dir, normalized_path).tr("\\", "/")
    zip_file.find_entry(relative_path)
  end
  private_class_method :find_video_entry

  def self.normalize_visibility(raw_visibility)
    visibility = raw_visibility.to_s
    return visibility if Post.visibilities.key?(visibility)

    Post.visibilities.key?("public_post") ? "public_post" : Post.visibilities.keys.first
  end
  private_class_method :normalize_visibility
end
