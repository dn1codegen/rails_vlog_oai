class PostsController < ApplicationController
  before_action :set_post, only: %i[show edit update destroy]
  before_action :require_authentication, only: %i[new create edit update destroy]
  before_action :authorize_post_owner!, only: %i[edit update destroy]

  def index
    @posts = Post.includes(:comments, video_attachment: :blob, thumbnail_attachment: :blob).order(created_at: :desc)
    @user_reactions_by_post_id = load_user_reactions(@posts)
  end

  def show
    if @post.video.attached? && (!@post.thumbnail.attached? || !@post.preview_frames.attached?)
      @post.request_thumbnail_generation
      @post.reload
    end

    @preview_frames = @post.preview_frames_attachments.includes(:blob).sort_by do |attachment|
      attachment.blob.metadata["percent"].to_i
    end
    @comments = @post.comments.order(created_at: :desc)
    @comment = @post.comments.build
    @media_info = MediaStreamInspector.inspect(@post.video.blob) if @post.video.attached?
    @current_user_reaction = current_user.post_reactions.find_by(post: @post) if user_signed_in?
  end

  def new
    @post = Post.new
  end

  def edit
  end

  def create
    @post = current_user.posts.build(post_params)

    if @post.save
      redirect_to @post, notice: "Видео опубликовано"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @post.update(post_params)
      @post.request_thumbnail_generation if @post.video.attached?
      redirect_to @post, notice: "Пост обновлен"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy
    redirect_to posts_path, notice: "Пост удален"
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def post_params
    params.require(:post).permit(:title, :description, :video)
  end

  def authorize_post_owner!
    return if @post.user == current_user

    redirect_to post_path(@post), alert: "Редактировать и удалять можно только свои посты."
  end

  def load_user_reactions(posts)
    return {} unless user_signed_in?

    post_ids = posts.map(&:id)
    return {} if post_ids.empty?

    current_user.post_reactions.where(post_id: post_ids).index_by(&:post_id)
  end
end
