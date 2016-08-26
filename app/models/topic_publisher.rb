class TopicPublisher
  attr_reader :topic, :publishing_api

  def initialize(topic:, publishing_api: PUBLISHING_API)
    @topic = topic
    @publishing_api = publishing_api
  end

  def save_draft(content_for_publication)
    save_catching_gds_api_errors do
      publishing_api.put_content(content_for_publication.content_id, content_for_publication.content_payload)
      publishing_api.patch_links(content_for_publication.content_id, content_for_publication.links_payload)
    end
  end

  def publish
    save_catching_gds_api_errors do
      publishing_api.publish(topic.content_id, topic.update_type)
    end
  end

private

  def save_catching_gds_api_errors
    begin
      ActiveRecord::Base.transaction do
        if topic.save
          yield

          Response.new(success: true)
        else
          Response.new(success: false)
        end
      end
    rescue GdsApi::HTTPErrorResponse => e
      Response.new(success: false, error: e.error_details['error']['message'])
    end
  end

  class Response
    def initialize(options = {})
      @success = options.fetch(:success)
      @error = options[:error]
    end

    def success?
      @success
    end

    attr_reader :error
  end
end
