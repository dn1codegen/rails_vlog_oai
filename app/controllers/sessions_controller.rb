class SessionsController < ApplicationController
  before_action :redirect_if_authenticated, only: %i[new create]

  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)

    if user&.authenticate(params[:password].to_s)
      session[:user_id] = user.id
      redirect_to root_path, notice: "Вы вошли в систему."
    else
      flash.now[:alert] = "Неверный email или пароль."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Вы вышли из системы."
  end
end
