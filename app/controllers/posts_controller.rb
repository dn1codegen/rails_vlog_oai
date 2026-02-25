class PostsController < ApplicationController
  before_action :set_post, only: %i[show edit update destroy]
  before_action :require_authentication, only: %i[new create edit update destroy]
  before_action :authorize_post_owner!, only: %i[edit update destroy]

  def index
    @query = params[:q].to_s.strip
    @posts = Post.includes(:comments, video_attachment: :blob, thumbnail_attachment: :blob).order(created_at: :desc)
    if @query.present?
      normalized_query = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
      @posts = @posts.where(
        "LOWER(posts.title) LIKE :query OR LOWER(COALESCE(posts.description, '')) LIKE :query",
        query: normalized_query
      )
    end
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
    @related_posts = load_related_posts(@post)
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

  def load_related_posts(post, limit: 10)
    base_scope = Post.where.not(id: post.id)
                     .includes(:comments, video_attachment: :blob, thumbnail_attachment: :blob)

    keyword_matches = []
    keywords = related_keywords(post)

    if keywords.any?
      query_chunks = keywords.map.with_index do |_word, index|
        "LOWER(posts.title) LIKE :q#{index} OR LOWER(COALESCE(posts.description, '')) LIKE :q#{index}"
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

  def related_keywords(post)
    stopwords = %w[
      a an and are as at be by for from in is of on or that the this to with
      в во и к на по с у не что это как для или но от до из
      пост видео vlog video
    ]

    [ post.title, post.description ].join(" ")
                                    .downcase
                                    .scan(/[\p{L}\p{N}]+/)
                                    .uniq
                                    .reject { |word| word.length < 3 || stopwords.include?(word) }
                                    .first(6)
  end
end
