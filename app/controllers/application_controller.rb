class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :user_signed_in?

  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id])
  end

  def user_signed_in?
    current_user.present?
  end

  def require_authentication
    return if user_signed_in?

    redirect_to new_session_path, alert: "Только зарегистрированные пользователи могут публиковать видео."
  end

  def redirect_if_authenticated
    return unless user_signed_in?

    redirect_to root_path, notice: "Вы уже вошли в систему."
  end
end
