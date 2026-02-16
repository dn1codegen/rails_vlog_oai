class GeneratePostThumbnailJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(post)
    result = VideoThumbnailGenerator.generate(post)
    return if %i[ok up_to_date no_video].include?(result.status)

    fallback_result = fallback_by_title(post)
    return if fallback_result&.status == :ok

    Rails.logger.warn(
      "Thumbnail generation failed for Post##{post.id}: #{result.status} #{result.message}. Fallback: #{fallback_result&.status} #{fallback_result&.message}"
    )
  end

  private

  def fallback_by_title(post)
    return nil unless internet_fallback_enabled?

    PostTitleImageFinder.attach_thumbnail(post)
  end

  def internet_fallback_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("INTERNET_THUMBNAIL_FALLBACK", "true"))
  end
end
