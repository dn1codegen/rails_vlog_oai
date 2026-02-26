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

  private

  def profile_params
    params.require(:user).permit(:name, :bio)
  end

  def require_profile_authentication
    return if user_signed_in?

    redirect_to new_session_path, alert: "Войдите, чтобы открыть профиль."
  end
end
