module Posts
  class ReactionsController < ApplicationController
    before_action :set_post
    before_action :require_reaction_authentication

    def create
      reaction_kind = params[:kind].to_s
      unless PostReaction.kinds.key?(reaction_kind)
        redirect_back fallback_location: fallback_path, alert: "Неизвестный тип реакции."
        return
      end

      reaction = current_user.post_reactions.find_or_initialize_by(post: @post)
      reaction.kind = reaction_kind

      if reaction.save
        redirect_back fallback_location: fallback_path, notice: "Реакция сохранена."
      else
        redirect_back fallback_location: fallback_path, alert: reaction.errors.full_messages.to_sentence
      end
    end

    private

    def set_post
      @post = Post.find(params[:post_id])
    end

    def require_reaction_authentication
      return if user_signed_in?

      redirect_to new_session_path, alert: "Только зарегистрированные пользователи могут ставить реакции."
    end

    def fallback_path
      post_path(@post, anchor: "reactions")
    end
  end
end
