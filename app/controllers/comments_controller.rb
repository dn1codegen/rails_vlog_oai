class CommentsController < ApplicationController
  before_action :set_post
  before_action :set_comment, only: %i[edit update destroy]

  def create
    @comment = @post.comments.build(comment_params)

    if @comment.save
      redirect_to post_path(@post, anchor: "comments"), notice: "Комментарий добавлен"
    else
      @comments = @post.comments.order(created_at: :desc)
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

  def set_comment
    @comment = @post.comments.find(params[:id])
  end

  def comment_params
    params.require(:comment).permit(:author_name, :body)
  end
end
