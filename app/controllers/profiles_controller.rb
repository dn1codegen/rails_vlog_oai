class ProfilesController < ApplicationController
  POSTS_PER_PAGE = 10

  before_action :require_profile_authentication

  def show
    @user = current_user
    @posts_count = @user.posts.count
    @total_pages = [ (@posts_count.to_f / POSTS_PER_PAGE).ceil, 1 ].max
    @current_page = [ normalize_page(params[:page]), @total_pages ].min
    @post_number_offset = (@current_page - 1) * POSTS_PER_PAGE

    @profile_posts = @user.posts
                          .includes(:comments, thumbnail_attachment: :blob)
                          .order(created_at: :desc)
                          .limit(POSTS_PER_PAGE)
                          .offset((@current_page - 1) * POSTS_PER_PAGE)
  end

  def edit
    @user = current_user
  end

  def update
    @user = current_user

    if @user.update(profile_params)
      redirect_to profile_path, notice: "Профиль обновлен."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def update_post_visibility
    post = current_user.posts.find_by(id: params[:id])
    unless post
      redirect_to profile_redirect_path, alert: "Можно менять видимость только своих постов."
      return
    end

    visibility = params[:visibility].to_s
    unless Post.visibilities.key?(visibility)
      redirect_to profile_redirect_path, alert: "Неверный тип видимости."
      return
    end

    if post.update(visibility:)
      redirect_to profile_redirect_path, notice: "Видимость поста обновлена."
    else
      redirect_to profile_redirect_path, alert: post.errors.full_messages.to_sentence
    end
  end

  def destroy_selected_posts
    post_ids = Array(params[:post_ids]).map(&:to_i).select(&:positive?).uniq
    if post_ids.empty?
      redirect_to profile_redirect_path, alert: "Выберите посты для удаления."
      return
    end

    posts = current_user.posts.where(id: post_ids)
    if posts.empty?
      redirect_to profile_redirect_path, alert: "Выбранные посты не найдены."
      return
    end

    deleted_count = posts.to_a.count(&:destroy)
    if deleted_count == posts.size
      redirect_to profile_redirect_path, notice: "Удалено постов: #{deleted_count}."
    elsif deleted_count.positive?
      redirect_to profile_redirect_path, alert: "Удалено постов: #{deleted_count}. Часть постов удалить не удалось."
    else
      redirect_to profile_redirect_path, alert: "Не удалось удалить выбранные посты."
    end
  end

  def destroy_all_posts
    posts = current_user.posts.to_a
    if posts.empty?
      redirect_to profile_path, alert: "У вас нет постов для удаления."
      return
    end

    deleted_count = posts.count(&:destroy)
    if deleted_count == posts.size
      redirect_to profile_path, notice: "Удалены все посты: #{deleted_count}."
    elsif deleted_count.positive?
      redirect_to profile_path, alert: "Удалено постов: #{deleted_count}. Часть постов удалить не удалось."
    else
      redirect_to profile_path, alert: "Не удалось удалить посты."
    end
  end

  def export_videos
    result = ProfileVideoArchiveExporter.call(user: current_user)
    if result.status != :ok
      redirect_to profile_path, alert: result.message.presence || "Не удалось сформировать архив видео."
      return
    end

    send_data result.data,
              type: result.content_type,
              filename: result.filename,
              disposition: :attachment
  end

  def import_videos
    result = ProfileVideoArchiveImporter.call(user: current_user, archive: params[:archive])
    if result.status != :ok
      preview_errors = result.errors.to_a.first(2).join(" | ")
      error_message = result.message.presence || "Не удалось импортировать архив."
      error_message = "#{error_message} #{preview_errors}" if preview_errors.present?
      redirect_to profile_path, alert: error_message
      return
    end

    if result.failed_count.positive?
      preview_errors = result.errors.first(3).join(" | ")
      redirect_to profile_path, alert: "Импортировано: #{result.imported_count}. Ошибок: #{result.failed_count}. #{preview_errors}"
    else
      redirect_to profile_path, notice: "Импортировано видео: #{result.imported_count}."
    end
  end

  private

  def profile_params
    params.require(:user).permit(:name, :bio)
  end

  def require_profile_authentication
    return if user_signed_in?

    redirect_to new_session_path, alert: "Войдите, чтобы открыть профиль."
  end

  def normalize_page(raw_page)
    value = raw_page.to_i
    value.positive? ? value : 1
  end

  def profile_redirect_path
    page = normalize_page(params[:page])
    return profile_path if page <= 1

    profile_path(page:)
  end
end
