class PostsController < ApplicationController
  before_action :set_post, only: %i[show edit update destroy]
  before_action :require_authentication, only: %i[new create edit update destroy fetch_description]
  before_action :authorize_post_owner!, only: %i[edit update destroy]

  def index
    @posts = Post.includes(:comments, video_attachment: :blob, thumbnail_attachment: :blob).order(created_at: :desc)
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

  def fetch_description
    result = VideoDescriptionFetcher.fetch(
      uploaded_file: params[:video],
      title_hint: params[:title]
    )

    if result.status == :ok
      render json: {
        status: "ok",
        description: result.description,
        source: result.source,
        query: result.query,
        source_order: result.source_order
      }
    else
      render json: {
        status: "error",
        message: result.message,
        query: result.query,
        source_order: result.source_order
      }, status: :unprocessable_entity
    end
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
end
