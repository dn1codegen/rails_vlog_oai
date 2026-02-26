require "test_helper"
require "zip"

class VlogFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "user creates video post and adds comment" do
    user = create_user(email: "creator@example.com")
    sign_in_as(user)

    inspection = VideoCodecInspector::Result.new(status: :ok, codec: "av1")

    with_forced_result(inspection) do
      assert_enqueued_with(job: GeneratePostThumbnailJob) do
        assert_difference("Post.count", 1) do
          post posts_path, params: {
            post: {
              title: "Первый выпуск",
              description: "Пробуем загрузку AV1 видео",
              video: uploaded_video
            }
          }
        end
      end
    end

    created_post = Post.order(:id).last

    assert_redirected_to post_path(created_post)
    follow_redirect!
    assert_response :success
    assert_match "Первый выпуск", response.body

    assert_difference("Comment.count", 1) do
      post post_comments_path(created_post), params: {
        comment: {
          body: "Очень понравилось видео!"
        }
      }
    end

    assert_redirected_to post_path(created_post, anchor: "comments")
    comment = Comment.order(:id).last
    assert_equal user, comment.user
    assert_equal user.email, comment.author_name
  end

  test "uses filename as post title when title is blank" do
    user = create_user(email: "auto-title@example.com")
    sign_in_as(user)

    inspection = VideoCodecInspector::Result.new(status: :ok, codec: "av1")

    with_forced_result(inspection) do
      assert_difference("Post.count", 1) do
        post posts_path, params: {
          post: {
            title: "",
            description: "Название должно проставиться автоматически",
            video: uploaded_video
          }
        }
      end
    end

    created_post = Post.order(:id).last
    assert_equal "sample", created_post.title
  end

  test "user creates post from youtube link and selected quality" do
    user = create_user(email: "youtube-author@example.com")
    sign_in_as(user)

    with_forced_result(VideoCodecInspector::Result.new(status: :ok, codec: "av1")) do
      with_forced_youtube_download_result(lambda do |post:, url:, quality:|
        assert_match "youtube.com", url
        assert_equal "medium", quality

        payload = File.binread(Rails.root.join("test/fixtures/files/sample.mp4"))
        post.video.attach(io: StringIO.new(payload), filename: "from-youtube.mp4", content_type: "video/mp4")

        YoutubeVideoImporter::DownloadResult.new(
          status: :ok,
          title: "Видео из YouTube",
          description: "Описание, подтянутое из YouTube"
        )
      end) do
        assert_difference("Post.count", 1) do
          post posts_path, params: {
            post: {
              title: "",
              description: "",
              tags: "rails, youtube",
              youtube_url: "https://www.youtube.com/watch?v=abc123",
              youtube_quality: "medium"
            }
          }
        end
      end
    end

    created_post = Post.order(:id).last
    assert_redirected_to post_path(created_post)
    assert_equal "Видео из YouTube", created_post.title
    assert_equal "Описание, подтянутое из YouTube", created_post.description
    assert created_post.video.attached?
  end

  test "returns youtube metadata for signed in user" do
    user = create_user(email: "youtube-options@example.com")
    sign_in_as(user)

    metadata_result = YoutubeVideoImporter::MetadataResult.new(
      status: :ok,
      title: "Sample video",
      description: "Sample description"
    )

    with_forced_youtube_metadata_result(metadata_result) do
      get youtube_options_posts_path, params: { url: "https://www.youtube.com/watch?v=abc123" }
    end

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "Sample video", payload.fetch("title")
    assert_equal "Sample description", payload.fetch("description")
    assert_not payload.key?("formats")
  end

  test "new post form shows youtube download button and progress bar" do
    user = create_user(email: "youtube-form@example.com")
    sign_in_as(user)

    get new_post_path

    assert_response :success
    assert_match "Скачать", response.body
    assert_match(/data-youtube-import-target=\"progress\"/, response.body)
    assert_match "Кто может видеть пост", response.body
    assert_match(/visibility-switch__input/, response.body)
    assert_match "Публичный", response.body
    assert_match "Личный", response.body
    assert_match(/quality-toggle__input/, response.body)
    assert_match "High", response.body
    assert_match "Medium", response.body
    assert_match "Low", response.body
  end

  test "private post is visible only to author" do
    owner = create_user(email: "private-owner@example.com")
    intruder = create_user(email: "private-intruder@example.com")
    sign_in_as(owner)

    with_forced_result(VideoCodecInspector::Result.new(status: :ok, codec: "av1")) do
      assert_difference("Post.count", 1) do
        post posts_path, params: {
          post: {
            title: "Приватный выпуск",
            description: "Этот пост видит только автор",
            visibility: "private_post",
            video: uploaded_video
          }
        }
      end
    end

    private_post = Post.order(:id).last
    assert_redirected_to post_path(private_post)
    assert private_post.visibility_private_post?

    get root_path
    assert_response :success
    assert_match "Приватный выпуск", response.body

    delete session_path
    assert_redirected_to root_path

    get root_path
    assert_response :success
    assert_no_match "Приватный выпуск", response.body

    get post_path(private_post)
    assert_redirected_to root_path

    sign_in_as(intruder)

    get root_path
    assert_response :success
    assert_no_match "Приватный выпуск", response.body

    get post_path(private_post)
    assert_redirected_to root_path

    assert_no_difference("Comment.count") do
      post post_comments_path(private_post), params: { comment: { body: "Не должно сохраниться" } }
    end
    assert_redirected_to root_path

    assert_no_difference("PostReaction.count") do
      post post_reaction_path(private_post), params: { kind: "like" }
    end
    assert_redirected_to root_path
  end

  test "rejects unsupported video codec on create" do
    user = create_user(email: "codec-check@example.com")
    sign_in_as(user)

    inspection = VideoCodecInspector::Result.new(status: :ok, codec: "mpeg2video")

    with_forced_result(inspection) do
      assert_no_difference("Post.count") do
        post posts_path, params: {
          post: {
            title: "Неподдерживаемый кодек",
            description: "Этот пост должен быть отклонен",
            video: uploaded_video
          }
        }
      end
    end

    assert_response :unprocessable_entity
    assert_match "кодек", response.body
  end

  test "user edits and deletes post" do
    owner = create_user(email: "owner@example.com")
    sign_in_as(owner)
    post_record = create_post_record(title: "Старый заголовок", user: owner)

    patch post_path(post_record), params: {
      post: {
        title: "Новый заголовок",
        description: "Обновленное описание"
      }
    }

    assert_redirected_to post_path(post_record)
    post_record.reload
    assert_equal "Новый заголовок", post_record.title

    assert_difference("Post.count", -1) do
      delete post_path(post_record)
    end

    assert_redirected_to posts_path
  end

  test "guest cannot create posts or comments" do
    post_record = create_post_record

    get new_post_path
    assert_redirected_to new_session_path

    assert_no_difference("Post.count") do
      post posts_path, params: {
        post: {
          title: "Гостевой пост",
          description: "Не должен сохраниться",
          video: uploaded_video
        }
      }
    end
    assert_redirected_to new_session_path

    assert_no_difference("Comment.count") do
      post post_comments_path(post_record), params: {
        comment: {
          body: "Я могу только комментировать"
        }
      }
    end
    assert_redirected_to new_session_path

    get youtube_options_posts_path, params: { url: "https://www.youtube.com/watch?v=abc123" }
    assert_redirected_to new_session_path
  end

  test "guest cannot open or update profile" do
    post_record = create_post_record

    get profile_path
    assert_redirected_to new_session_path

    patch profile_path, params: { user: { name: "Новый ник" } }
    assert_redirected_to new_session_path

    patch profile_post_visibility_path(post_record), params: { visibility: "private_post" }
    assert_redirected_to new_session_path

    get export_videos_profile_path
    assert_redirected_to new_session_path

    post import_videos_profile_path
    assert_redirected_to new_session_path

    delete destroy_selected_posts_profile_path
    assert_redirected_to new_session_path

    delete destroy_all_posts_profile_path
    assert_redirected_to new_session_path
  end

  test "user can open and update profile" do
    user = create_user(email: "profile-owner@example.com")
    public_profile_post = create_post_record(title: "Публичный профильный пост", user:, visibility: "public_post")
    private_profile_post = create_post_record(title: "Личный профильный пост", user:, visibility: "private_post")
    sign_in_as(user)

    get profile_path
    assert_response :success
    assert_match "profile-owner@example.com", response.body
    assert_match edit_post_path(public_profile_post), response.body
    assert_match edit_post_path(private_profile_post), response.body
    assert_equal 2, response.body.scan("profile-post-delete-form").size
    assert_match destroy_selected_posts_profile_path, response.body
    assert_match "Удалить выбранные", response.body
    assert_match "Экспортировать выбранные", response.body
    assert_match "ВЫДЕЛИТЬ ВСЕ ПОСТЫ", response.body
    assert_match "profile-selected-posts-#{user.id}", response.body
    assert_match "togglePostSelection", response.body
    assert_no_match "Удалить все посты", response.body
    assert_no_match "Скачать архив моих видео", response.body

    patch profile_path, params: {
      user: {
        name: "Автор канала",
        bio: "Пишу про Ruby и видео."
      }
    }
    assert_redirected_to profile_path
    follow_redirect!
    assert_response :success
    assert_match "Профиль обновлен", response.body
    assert_match "Автор канала", response.body
    assert_match "Пишу про Ruby и видео.", response.body

    user.reload
    assert_equal "Автор канала", user.name
    assert_equal "Пишу про Ruby и видео.", user.bio
  end

  test "profile paginates posts by 10 and shows total count in heading" do
    user = create_user(email: "profile-pagination@example.com")
    created_posts = 12.times.map do |index|
      create_post_record(title: "Пост профиля #{index + 1}", user:, visibility: "public_post")
    end
    sign_in_as(user)

    get profile_path
    assert_response :success
    assert_match "Мои видео (12)", response.body
    assert_match "Страница 1 из 2", response.body
    assert_match profile_path(page: 2), response.body
    assert_equal 10, response.body.scan("profile-post-delete-form").size
    assert_equal 10, response.body.scan("profile-post__checkbox").size
    assert_match "№1", response.body
    assert_match "№10", response.body
    assert_no_match post_path(created_posts.first), response.body
    assert_match post_path(created_posts.last), response.body

    get profile_path, params: { page: 2 }
    assert_response :success
    assert_match "Мои видео (12)", response.body
    assert_match "Страница 2 из 2", response.body
    assert_match profile_path(page: 1), response.body
    assert_equal 2, response.body.scan("profile-post-delete-form").size
    assert_equal 2, response.body.scan("profile-post__checkbox").size
    assert_match "№11", response.body
    assert_match "№12", response.body
    assert_match post_path(created_posts.first), response.body
    assert_match post_path(created_posts.second), response.body
    assert_no_match post_path(created_posts.last), response.body
  end

  test "user can delete selected posts from profile list" do
    user = create_user(email: "profile-bulk-delete@example.com")
    first_post = create_post_record(title: "Первый для удаления", user:, visibility: "public_post")
    second_post = create_post_record(title: "Второй для удаления", user:, visibility: "public_post")
    kept_post = create_post_record(title: "Оставшийся пост", user:, visibility: "public_post")
    sign_in_as(user)

    assert_difference("Post.count", -2) do
      delete destroy_selected_posts_profile_path, params: { post_ids: [ first_post.id, second_post.id ], page: 1 }
    end

    assert_redirected_to profile_path
    follow_redirect!
    assert_response :success
    assert_match "Удалено постов: 2", response.body
    assert_no_match first_post.title, response.body
    assert_no_match second_post.title, response.body
    assert_match kept_post.title, response.body
  end

  test "user can delete all posts from profile list" do
    user = create_user(email: "profile-delete-all@example.com")
    create_post_record(title: "Пост для полного удаления 1", user:, visibility: "public_post")
    create_post_record(title: "Пост для полного удаления 2", user:, visibility: "public_post")
    sign_in_as(user)

    assert_difference("Post.count", -2) do
      delete destroy_all_posts_profile_path
    end

    assert_redirected_to profile_path
    follow_redirect!
    assert_response :success
    assert_match "Удалены все посты: 2", response.body
    assert_match "Вы пока не опубликовали ни одного видео.", response.body
  end

  test "user deletes post from profile and stays on profile page" do
    user = create_user(email: "profile-delete@example.com")
    post_record = create_post_record(title: "Пост для удаления из профиля", user:, visibility: "public_post")
    sign_in_as(user)

    assert_difference("Post.count", -1) do
      delete post_path(post_record), params: { from_profile: true }
    end

    assert_redirected_to profile_path
    follow_redirect!
    assert_response :success
    assert_no_match "Пост для удаления из профиля", response.body
  end

  test "user can export selected videos to zip with json manifest" do
    user = create_user(email: "profile-export@example.com")
    first_post = create_post_record(title: "Экспортируемое видео 1", user:, tags: "rails", visibility: "private_post")
    second_post = create_post_record(title: "Экспортируемое видео 2", user:, tags: "api", visibility: "public_post")
    skipped_post = create_post_record(title: "Не должен попасть в архив", user:, tags: "skip", visibility: "public_post")
    sign_in_as(user)

    get export_videos_profile_path, params: { post_ids: [ first_post.id, second_post.id ], page: 1 }

    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_match "attachment", response.headers["Content-Disposition"]

    Zip::File.open_buffer(response.body) do |zip_file|
      manifest_entry = zip_file.find_entry("posts.json")
      assert manifest_entry

      manifest = JSON.parse(manifest_entry.get_input_stream.read)
      assert_equal "vlog_posts_archive", manifest["format"]
      assert_equal 1, manifest["version"]
      assert_equal 2, manifest["posts"].size
      assert_equal user.email, manifest.dig("user", "email")

      exported_titles = manifest["posts"].map { |payload| payload["title"] }
      assert_includes exported_titles, first_post.title
      assert_includes exported_titles, second_post.title
      assert_not_includes exported_titles, skipped_post.title

      manifest["posts"].each do |payload|
        assert payload["video_path"].present?
        assert zip_file.find_entry(payload["video_path"])
      end
    end
  end

  test "user cannot export videos without selected posts" do
    user = create_user(email: "profile-export-empty@example.com")
    create_post_record(title: "Пост без выделения", user:, visibility: "public_post")
    sign_in_as(user)

    get export_videos_profile_path

    assert_redirected_to profile_path
    follow_redirect!
    assert_response :success
    assert_match "Выберите посты для экспорта.", response.body
  end

  test "user can import videos from exported archive" do
    owner = create_user(email: "profile-export-owner@example.com")
    create_post_record(title: "Архивный ролик 1", user: owner, tags: "rails", visibility: "private_post")
    create_post_record(title: "Архивный ролик 2", user: owner, tags: "backend", visibility: "public_post")

    sign_in_as(owner)
    get export_videos_profile_path, params: { post_ids: owner.posts.ids }
    assert_response :success
    archive_payload = response.body

    delete session_path
    assert_redirected_to root_path

    importer = create_user(email: "profile-importer@example.com")
    sign_in_as(importer)

    archive_file = Tempfile.new([ "profile-import-", ".zip" ])
    archive_file.binmode
    archive_file.write(archive_payload)
    archive_file.rewind

    upload = Rack::Test::UploadedFile.new(
      archive_file.path,
      "application/zip",
      original_filename: "videos-archive.zip"
    )

    with_forced_result(VideoCodecInspector::Result.new(status: :ok, codec: "av1")) do
      assert_difference("Post.count", 2) do
        post import_videos_profile_path, params: { archive: upload }
      end
    end

    assert_redirected_to profile_path
    follow_redirect!
    assert_match "Импортировано видео: 2", response.body

    imported_posts = importer.posts.order(:id)
    assert_equal 2, imported_posts.count
    assert_equal [ "Архивный ролик 1", "Архивный ролик 2" ], imported_posts.pluck(:title)
    assert imported_posts.all? { |post| post.video.attached? }
    assert_equal %w[private_post public_post].sort, imported_posts.map(&:visibility).sort
  ensure
    archive_file&.close
    archive_file&.unlink
  end

  test "archive import skips codec re-validation for exported videos" do
    owner = create_user(email: "profile-export-owner-codec@example.com")
    create_post_record(title: "Кодек архив 1", user: owner, tags: "rails", visibility: "private_post")
    create_post_record(title: "Кодек архив 2", user: owner, tags: "backend", visibility: "public_post")

    sign_in_as(owner)
    get export_videos_profile_path, params: { post_ids: owner.posts.ids }
    assert_response :success
    archive_payload = response.body

    delete session_path
    assert_redirected_to root_path

    importer = create_user(email: "profile-importer-codec@example.com")
    sign_in_as(importer)

    archive_file = Tempfile.new([ "profile-import-codec-", ".zip" ])
    archive_file.binmode
    archive_file.write(archive_payload)
    archive_file.rewind

    upload = Rack::Test::UploadedFile.new(
      archive_file.path,
      "application/zip",
      original_filename: "videos-archive-codec.zip"
    )

    with_forced_result(VideoCodecInspector::Result.new(status: :ok, codec: "mpeg2video")) do
      assert_difference("Post.count", 2) do
        post import_videos_profile_path, params: { archive: upload }
      end
    end

    assert_redirected_to profile_path
    follow_redirect!
    assert_match "Импортировано видео: 2", response.body
    assert_equal 2, importer.posts.count
  ensure
    archive_file&.close
    archive_file&.unlink
  end

  test "user can import videos from repacked archive with nested root folder" do
    owner = create_user(email: "profile-export-owner-nested@example.com")
    create_post_record(title: "Вложенный архив 1", user: owner, tags: "rails", visibility: "private_post")
    create_post_record(title: "Вложенный архив 2", user: owner, tags: "backend", visibility: "public_post")

    sign_in_as(owner)
    get export_videos_profile_path, params: { post_ids: owner.posts.ids }
    assert_response :success
    raw_archive_payload = response.body

    wrapped_archive_payload = Zip::OutputStream.write_buffer do |output_stream|
      Zip::File.open_buffer(raw_archive_payload) do |source_zip|
        source_zip.each do |entry|
          next if entry.directory?

          output_stream.put_next_entry(File.join("saved_export", entry.name))
          output_stream.write(entry.get_input_stream.read)
        end
      end
    end.string

    delete session_path
    assert_redirected_to root_path

    importer = create_user(email: "profile-importer-nested@example.com")
    sign_in_as(importer)

    archive_file = Tempfile.new([ "profile-import-nested-", ".zip" ])
    archive_file.binmode
    archive_file.write(wrapped_archive_payload)
    archive_file.rewind

    upload = Rack::Test::UploadedFile.new(
      archive_file.path,
      "application/zip",
      original_filename: "saved-export.zip"
    )

    with_forced_result(VideoCodecInspector::Result.new(status: :ok, codec: "av1")) do
      assert_difference("Post.count", 2) do
        post import_videos_profile_path, params: { archive: upload }
      end
    end

    assert_redirected_to profile_path
    follow_redirect!
    assert_match "Импортировано видео: 2", response.body
    assert_equal 2, importer.posts.count
  ensure
    archive_file&.close
    archive_file&.unlink
  end

  test "user can toggle post visibility from profile list" do
    user = create_user(email: "visibility-owner@example.com")
    post_record = create_post_record(title: "Пост для переключения", user:, visibility: "public_post")
    create_post_record(title: "Дополнительный пост 1", user:, visibility: "public_post")
    create_post_record(title: "Дополнительный пост 2", user:, visibility: "public_post")
    create_post_record(title: "Дополнительный пост 3", user:, visibility: "public_post")
    create_post_record(title: "Дополнительный пост 4", user:, visibility: "public_post")
    create_post_record(title: "Дополнительный пост 5", user:, visibility: "public_post")
    create_post_record(title: "Дополнительный пост 6", user:, visibility: "public_post")
    create_post_record(title: "Дополнительный пост 7", user:, visibility: "public_post")
    create_post_record(title: "Дополнительный пост 8", user:, visibility: "public_post")
    create_post_record(title: "Дополнительный пост 9", user:, visibility: "public_post")
    create_post_record(title: "Дополнительный пост 10", user:, visibility: "public_post")
    sign_in_as(user)

    patch profile_post_visibility_path(post_record), params: { visibility: "private_post", page: 2 }
    assert_redirected_to profile_path(page: 2)
    post_record.reload
    assert post_record.visibility_private_post?

    patch profile_post_visibility_path(post_record), params: { visibility: "public_post", page: 2 }
    assert_redirected_to profile_path(page: 2)
    post_record.reload
    assert post_record.visibility_public_post?
  end

  test "user cannot toggle visibility of another user's post from profile list" do
    owner = create_user(email: "visibility-owner-two@example.com")
    intruder = create_user(email: "visibility-intruder@example.com")
    post_record = create_post_record(title: "Чужой видимый пост", user: owner, visibility: "public_post")
    sign_in_as(intruder)

    patch profile_post_visibility_path(post_record), params: { visibility: "private_post" }
    assert_redirected_to profile_path
    follow_redirect!
    assert_match "только своих постов", response.body
    assert post_record.reload.visibility_public_post?
  end

  test "guest cannot set post reaction" do
    post_record = create_post_record

    assert_no_difference("PostReaction.count") do
      post post_reaction_path(post_record), params: { kind: "like" }
    end

    assert_redirected_to new_session_path
  end

  test "filters posts by query on index" do
    create_post_record(title: "Ruby on Rails обзор", tags: "rails, backend")
    create_post_record(title: "Go microservices")

    get root_path, params: { q: "rails" }

    assert_response :success
    assert_match "Ruby on Rails обзор", response.body
    assert_no_match "Go microservices", response.body
    assert_match "Результаты поиска", response.body
  end

  test "user can add tags to post" do
    user = create_user(email: "tagger@example.com")
    sign_in_as(user)

    inspection = VideoCodecInspector::Result.new(status: :ok, codec: "av1")

    with_forced_result(inspection) do
      assert_difference("Post.count", 1) do
        post posts_path, params: {
          post: {
            title: "Видео с тегами",
            description: "Проверка тегов",
            tags: "#Rails, API Design, rails",
            video: uploaded_video
          }
        }
      end
    end

    created_post = Post.order(:id).last
    assert_equal "rails, api-design", created_post.tags

    get post_path(created_post)
    assert_response :success
    assert_match "#rails", response.body
    assert_match "#api-design", response.body

    get root_path, params: { q: "api-design" }
    assert_response :success
    assert_match "Видео с тегами", response.body
  end

  test "user can like and dislike post with counters" do
    user = create_user(email: "reactor@example.com")
    post_record = create_post_record
    sign_in_as(user)

    assert_difference("PostReaction.count", 1) do
      post post_reaction_path(post_record), params: { kind: "like" }
    end
    assert_redirected_to post_path(post_record, anchor: "reactions")
    post_record.reload
    assert_equal 1, post_record.likes_count
    assert_equal 0, post_record.dislikes_count
    assert_equal "like", PostReaction.find_by(post: post_record, user: user)&.kind

    assert_no_difference("PostReaction.count") do
      post post_reaction_path(post_record), params: { kind: "dislike" }
    end
    assert_redirected_to post_path(post_record, anchor: "reactions")
    post_record.reload
    assert_equal 0, post_record.likes_count
    assert_equal 1, post_record.dislikes_count
    assert_equal "dislike", PostReaction.find_by(post: post_record, user: user)&.kind

    get post_path(post_record)
    assert_response :success
    assert_match(/aria-label=\"Понравилось \(0\)\"/, response.body)
    assert_match(/aria-label=\"Не понравилось \(1\)\"/, response.body)
  end

  test "non-owner cannot edit or delete another user's post" do
    owner = create_user(email: "owner-two@example.com")
    intruder = create_user(email: "intruder@example.com")
    post_record = create_post_record(title: "Чужой пост", user: owner)
    sign_in_as(intruder)

    patch post_path(post_record), params: {
      post: {
        title: "Взлом",
        description: "Изменение не должно примениться"
      }
    }
    assert_redirected_to post_path(post_record)
    follow_redirect!
    assert_match "только свои посты", response.body
    assert_equal "Чужой пост", post_record.reload.title

    assert_no_difference("Post.count") do
      delete post_path(post_record)
    end
    assert_redirected_to post_path(post_record)
  end

  test "user edits and deletes comment" do
    user = create_user(email: "comment-owner@example.com")
    sign_in_as(user)
    post_record = create_post_record
    comment = post_record.comments.create!(user:, body: "Первый комментарий")

    patch post_comment_path(post_record, comment), params: {
      comment: {
        body: "Обновленный комментарий"
      }
    }

    assert_redirected_to post_path(post_record, anchor: "comments")
    comment.reload
    assert_equal user.email, comment.author_name
    assert_equal "Обновленный комментарий", comment.body

    assert_difference("Comment.count", -1) do
      delete post_comment_path(post_record, comment)
    end

    assert_redirected_to post_path(post_record, anchor: "comments")
  end

  test "non-owner cannot edit or delete another user's comment" do
    owner = create_user(email: "comment-real-owner@example.com")
    intruder = create_user(email: "comment-intruder@example.com")
    post_record = create_post_record(user: owner)
    comment = post_record.comments.create!(user: owner, body: "Чужой комментарий")
    sign_in_as(intruder)

    patch post_comment_path(post_record, comment), params: {
      comment: {
        body: "Попытка изменить"
      }
    }
    assert_redirected_to post_path(post_record, anchor: "comments")
    follow_redirect!
    assert_match "только свои комментарии", response.body
    assert_equal "Чужой комментарий", comment.reload.body

    assert_no_difference("Comment.count") do
      delete post_comment_path(post_record, comment)
    end
    assert_redirected_to post_path(post_record, anchor: "comments")
  end

  test "shows video and audio codec info on post page" do
    post_record = create_post_record
    expected_file_size = ApplicationController.helpers.format_file_size(post_record.video.blob.byte_size)

    media_result = MediaStreamInspector::Result.new(
      status: :ok,
      video_codec: "hevc",
      audio_codec: "aac",
      video_resolution: "3840x2160",
      video_bitrate: 8_500_000,
      audio_bitrate: 192_000,
      format_name: "mov,mp4,m4a,3gp,3g2,mj2"
    )

    with_forced_media_result(media_result) do
      get post_path(post_record)
    end

    assert_response :success
    assert_match "Информация о видео", response.body
    assert_match(/<strong>\s*Видео:\s*<\/strong>/, response.body)
    assert_match "hevc", response.body
    assert_match "3840x2160", response.body
    assert_match "8.5 Мбит/с", response.body
    assert_match(/<strong>\s*Аудио:\s*<\/strong>/, response.body)
    assert_match "aac", response.body
    assert_match "192 кбит/с", response.body
    assert_match(/<strong>\s*Размер файла:\s*<\/strong>/, response.body)
    assert_match Regexp.new(Regexp.escape(expected_file_size)), response.body
  end

  test "shows related posts sidebar on post page" do
    current_post = create_post_record(title: "Rails авторизация")
    related_post = create_post_record(title: "Rails роутинг")
    create_post_record(title: "Кулинарный влог")

    get post_path(current_post)

    assert_response :success
    assert_match "Похожие видео", response.body
    assert_match post_path(related_post), response.body
  end

  private

  def uploaded_video
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/sample.mp4"),
      "video/mp4"
    )
  end

  def create_user(email:)
    User.create!(
      email:,
      password: "Password123",
      password_confirmation: "Password123"
    )
  end

  def sign_in_as(user)
    post session_path, params: { email: user.email, password: "Password123" }
    assert_redirected_to root_path
  end

  def with_forced_result(result)
    previous = VideoCodecInspector.forced_result
    VideoCodecInspector.forced_result = result
    yield
  ensure
    VideoCodecInspector.forced_result = previous
  end

  def with_forced_media_result(result)
    previous = MediaStreamInspector.forced_result
    MediaStreamInspector.forced_result = result
    yield
  ensure
    MediaStreamInspector.forced_result = previous
  end

  def with_forced_youtube_metadata_result(result)
    previous = YoutubeVideoImporter.forced_metadata_result
    YoutubeVideoImporter.forced_metadata_result = result
    yield
  ensure
    YoutubeVideoImporter.forced_metadata_result = previous
  end

  def with_forced_youtube_download_result(result)
    previous = YoutubeVideoImporter.forced_download_result
    YoutubeVideoImporter.forced_download_result = result
    yield
  ensure
    YoutubeVideoImporter.forced_download_result = previous
  end

  def create_post_record(title: "Тестовый пост", user: nil, tags: "", visibility: "public_post")
    post_record = Post.new(
      user: user || create_user(email: "post-owner-#{SecureRandom.hex(4)}@example.com"),
      title:,
      description: "Описание",
      tags:,
      visibility:
    )
    with_forced_result(VideoCodecInspector::Result.new(status: :ok, codec: "av1")) do
      File.open(Rails.root.join("test/fixtures/files/sample.mp4")) do |file|
        post_record.video.attach(io: file, filename: "sample.mp4", content_type: "video/mp4")
        post_record.save!
      end
    end

    post_record
  end
end
