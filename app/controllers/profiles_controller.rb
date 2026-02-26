class ProfilesController < ApplicationController
  before_action :require_profile_authentication

  def show
    @user = current_user
    @recent_posts = @user.posts
                         .includes(:comments, thumbnail_attachment: :blob)
                         .order(created_at: :desc)
                         .limit(6)
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
      redirect_to profile_path, alert: "Можно менять видимость только своих постов."
      return
    end

    visibility = params[:visibility].to_s
    unless Post.visibilities.key?(visibility)
      redirect_to profile_path, alert: "Неверный тип видимости."
      return
    end

    if post.update(visibility:)
      redirect_to profile_path, notice: "Видимость поста обновлена."
    else
      redirect_to profile_path, alert: post.errors.full_messages.to_sentence
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
end
