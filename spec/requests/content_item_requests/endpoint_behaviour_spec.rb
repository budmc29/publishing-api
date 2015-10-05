require "rails_helper"

RSpec.describe "Endpoint behaviour", type: :request do
  context "/content" do
    let(:content_item) { content_item_without_access_limiting }
    let(:request_body) { content_item.to_json }
    let(:request_path) { "/content#{base_path}" }

    returns_200_response
    returns_400_on_invalid_json
    suppresses_draft_content_store_502s
    forwards_locale_extension
    accepts_root_path

    context "without a content id" do
      let(:request_body) {
        content_item.except(:content_id)
      }

      creates_no_derived_representations
    end
  end

  context "/draft-content" do
    let(:content_item) { content_item_with_access_limiting }
    let(:request_body) { content_item.to_json }
    let(:request_path) { "/draft-content#{base_path}" }

    returns_200_response
    returns_400_on_invalid_json
    suppresses_draft_content_store_502s
    forwards_locale_extension
    accepts_root_path

    context "without a content id" do
      let(:request_body) {
        content_item.except(:content_id)
      }

      creates_no_derived_representations
    end
  end
end
