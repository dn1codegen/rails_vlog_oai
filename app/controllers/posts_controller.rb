class PostsController < ApplicationController
  before_action :set_post, only: %i[show edit update destroy]
  before_action :require_authentication, only: %i[new create edit update destroy youtube_options]
  before_action :authorize_post_visibility!, only: %i[show]
  before_action :authorize_post_owner!, only: %i[edit update destroy]

  def index
    @query = params[:q].to_s.strip
    @selected_tag = normalize_selected_tag(params[:tag])
    @posts = Post.visible_to(current_user)
                 .includes(:user, :comments, video_attachment: :blob, thumbnail_attachment: :blob, cover_image_attachment: :blob)
                 .order(created_at: :desc)

    if @selected_tag.present?
      @posts = @posts.where(
        "posts.tags = :tag OR posts.tags LIKE :prefix OR posts.tags LIKE :middle OR posts.tags LIKE :suffix",
        tag: @selected_tag,
        prefix: "#{@selected_tag}, %",
        middle: "%, #{@selected_tag}, %",
        suffix: "%, #{@selected_tag}"
      )
    end

    if @query.present?
      normalized_query = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
      @posts = @posts.where(
        "LOWER(posts.title) LIKE :query OR LOWER(COALESCE(posts.description, '')) LIKE :query OR LOWER(COALESCE(posts.tags, '')) LIKE :query",
        query: normalized_query
      )
    end
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
    @related_posts = load_related_posts(@post)
  end

  def new
    @post = Post.new
  end

  def edit
  end

  def create
    @post = build_post_for_create
    unless process_youtube_import(@post)
      render :new, status: :unprocessable_entity
      return
    end

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
    redirect_to destroy_redirect_path, notice: "Пост удален"
  end

  def youtube_options
    result = YoutubeVideoImporter.metadata(params[:url].to_s)
    if result.status == :ok
      render json: {
        title: result.title,
        description: result.description
      }
    else
      render json: {
        error: result.message.presence || "Не удалось получить метаданные YouTube",
        title: result.title,
        description: result.description
      }, status: :unprocessable_entity
    end
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def post_params
    params.require(:post).permit(:title, :description, :visibility, :video, :cover_image, :youtube_url, :youtube_quality, selected_tags: [])
  end

  def build_post_for_create
    attributes = post_params
    post = current_user.posts.build(attributes.except(:youtube_url, :youtube_quality))
    assign_youtube_attributes(post, attributes)
    post
  end

  def assign_youtube_attributes(post, attributes)
    post.youtube_url = attributes[:youtube_url].to_s.strip
    post.youtube_quality = attributes[:youtube_quality].to_s.strip
  end

  def process_youtube_import(post)
    return true if post.video.attached?
    return true if post.youtube_url.blank?

    result = YoutubeVideoImporter.download_and_attach(
      post:,
      url: post.youtube_url,
      quality: post.youtube_quality.presence
    )
    if result.status != :ok
      post.errors.add(:video, result.message.presence || "Не удалось скачать видео по ссылке YouTube")
      return false
    end

    apply_youtube_metadata(post, result)
    true
  end

  def apply_youtube_metadata(post, result)
    post.title = result.title.to_s.strip[0, 120] if post.title.blank? && result.title.present?
    post.description = result.description.to_s.strip[0, 5000] if post.description.blank? && result.description.present?
  end

  def authorize_post_owner!
    return if @post.user == current_user

    redirect_to post_path(@post), alert: "Редактировать и удалять можно только свои посты."
  end

  def authorize_post_visibility!
    return if @post.visible_to?(current_user)

    redirect_to root_path, alert: "Этот пост приватный и доступен только автору."
  end

  def load_related_posts(post, limit: 10)
    base_scope = Post.visible_to(current_user)
                     .where.not(id: post.id)
                     .includes(:comments, video_attachment: :blob, thumbnail_attachment: :blob, cover_image_attachment: :blob)

    keyword_matches = []
    keywords = related_keywords(post)

    if keywords.any?
      query_chunks = keywords.map.with_index do |_word, index|
        "LOWER(posts.title) LIKE :q#{index} OR LOWER(COALESCE(posts.description, '')) LIKE :q#{index} OR LOWER(COALESCE(posts.tags, '')) LIKE :q#{index}"
      end
      query_binds = keywords.each_with_index.to_h do |keyword, index|
        [ :"q#{index}", "%#{ActiveRecord::Base.sanitize_sql_like(keyword)}%" ]
      end

      keyword_matches = base_scope.where(query_chunks.join(" OR "), query_binds)
                                  .order(created_at: :desc)
                                  .limit(limit)
                                  .to_a
    end

    return keyword_matches if keyword_matches.size >= limit

    fallback_posts = base_scope.where.not(id: keyword_matches.map(&:id))
                               .order(created_at: :desc)
                               .limit(limit - keyword_matches.size)
                               .to_a

    keyword_matches + fallback_posts
  end

  def destroy_redirect_path
    if params[:from_profile].to_s == "true" || params[:from_profile].to_s == "1"
      page = params[:page].to_i
      return profile_path if page <= 1

      return profile_path(page:)
    end

    posts_path
  end

  def related_keywords(post)
    stopwords = %w[
      a an and are as at be by for from in is of on or that the this to with
      в во и к на по с у не что это как для или но от до из
      пост видео vlog video
    ]

    [ post.title, post.description, post.tags ].join(" ")
                                    .downcase
                                    .scan(/[\p{L}\p{N}]+/)
                                    .uniq
                                    .reject { |word| word.length < 3 || stopwords.include?(word) }
                                    .first(6)
  end

  def normalize_selected_tag(raw_tag)
    tag = raw_tag.to_s.strip
    return if tag.blank?

    Post::ALLOWED_TAGS.find { |allowed_tag| allowed_tag.casecmp?(tag) }
  end
end
