class CommentsController < ApplicationController
  before_action :set_post
  before_action :require_comment_authentication
  before_action :set_comment, only: %i[edit update destroy]
  before_action :authorize_comment_owner!, only: %i[edit update destroy]

  def create
    @comment = @post.comments.build(comment_params.merge(user: current_user))

    if @comment.save
      redirect_to post_path(@post, anchor: "comments"), notice: "Комментарий добавлен"
    else
      prepare_post_show_context
      render "posts/show", status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @comment.update(comment_params)
      redirect_to post_path(@post, anchor: "comments"), notice: "Комментарий обновлен"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @comment.destroy
    redirect_to post_path(@post, anchor: "comments"), notice: "Комментарий удален"
  end

  private

  def set_post
    @post = Post.find(params[:post_id])
  end

  def require_comment_authentication
    return if user_signed_in?

    redirect_to new_session_path, alert: "Только зарегистрированные пользователи могут оставлять комментарии."
  end

  def set_comment
    @comment = @post.comments.find(params[:id])
  end

  def authorize_comment_owner!
    return if @comment.user == current_user

    redirect_to post_path(@post, anchor: "comments"), alert: "Редактировать и удалять можно только свои комментарии."
  end

  def comment_params
    params.require(:comment).permit(:body)
  end

  def prepare_post_show_context
    @comments = @post.comments.order(created_at: :desc)
    @preview_frames = @post.preview_frames_attachments.includes(:blob).sort_by do |attachment|
      attachment.blob.metadata["percent"].to_i
    end

    @media_info = MediaStreamInspector.inspect(@post.video.blob) if @post.video.attached?
  end
end
