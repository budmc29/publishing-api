class ContentItemsController < ApplicationController
  def live_content_item
    url_arbiter.reserve_path(
      base_path,
      publishing_app: content_item[:publishing_app]
    )

    begin
      draft_content_store.put_content_item(content_item)
    rescue GdsApi::HTTPServerError => e
      unless e.code == 502 && ENV["SUPPRESS_DRAFT_STORE_502_ERROR"]
        raise e
      end
    end

    response = live_content_store.put_content_item(content_item)

    render json: content_item, content_type: response.headers[:content_type]
  rescue GOVUK::Client::Errors::UnprocessableEntity => e
    render json: e.response, status: 422
  rescue GOVUK::Client::Errors::Conflict => e
    render json: e.response, status: 409
  end

private

  def url_arbiter
    PublishingAPI.services(:url_arbiter)
  end

  def draft_content_store
    PublishingAPI.services(:draft_content_store)
  end

  def live_content_store
    PublishingAPI.services(:live_content_store)
  end

  def content_item
    super.except(:access_limited)
  end
end
