class GeneratePostThumbnailJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(post)
    result = VideoThumbnailGenerator.generate(post)
    return if %i[ok up_to_date no_video].include?(result.status)

    Rails.logger.warn(
      "Thumbnail generation failed for Post##{post.id}: #{result.status} #{result.message}"
    )
  end
end
