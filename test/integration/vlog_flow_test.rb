require "test_helper"

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
    assert_match(/aria-label=\"Лайк \(0\)\"/, response.body)
    assert_match(/aria-label=\"Дизлайк \(1\)\"/, response.body)
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

  def create_post_record(title: "Тестовый пост", user: nil, tags: "")
    post_record = Post.new(
      user: user || create_user(email: "post-owner-#{SecureRandom.hex(4)}@example.com"),
      title:,
      description: "Описание",
      tags:
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
