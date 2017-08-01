require "rails_helper"

RSpec.describe V2::EditionsController do
  def u(string)
    CGI.escape(string)
  end

  describe "index" do
    before(:context) do
      Timecop.freeze("2017-01-01 09:00:00.1") do
        50.times do |index|
          FactoryGirl.create(
            :draft_edition,
            id: index + 1,
            document: FactoryGirl.create(:document, locale: "fr"),
            base_path: "/content#{index + 1}",
          )
        end
      end

      Timecop.freeze("2017-01-01 09:00:00.2") do
        50.times do |index|
          FactoryGirl.create(
            :live_edition,
            id: index + 51,
            document: FactoryGirl.create(:document),
            base_path: "/content#{index + 51}",
          )
        end
      end

      Timecop.freeze("2017-01-01 09:00:00.3") do
        50.times do |index|
          FactoryGirl.create(
            :unpublished_edition,
            id: index + 101,
            document: FactoryGirl.create(:document),
            base_path: "/content#{index + 101}",
            publishing_app: "test",
          )
        end
      end
    end

    after(:context) do
      Edition.delete_all
      Document.delete_all
    end

    context "all editions" do
      it "returns the correct list for the first page" do
        get :index
        expect(parsed_response["results"].count).to eq(100)
        expect(parsed_response["links"]).to eq([
          { "href" => "http://test.host/v2/editions?after=#{u('2017-01-01T09:00:00.200000Z,100')}", "rel" => "next" },
          { "href" => "http://test.host/v2/editions", "rel" => "self" },
        ])
        expect(parsed_response["results"].first.keys)
          .to_not include(%w(id document_id))
      end

      it "returns the correct list for the second page" do
        get :index, params: { after: "2017-01-01T09:00:00.200000Z,100" }
        expect(parsed_response["results"].count).to eq(50)
        expect(parsed_response["links"]).to eq([
          { "href" => "http://test.host/v2/editions?after=#{u('2017-01-01T09:00:00.200000Z,100')}", "rel" => "self" },
          { "href" => "http://test.host/v2/editions?before=#{u('2017-01-01T09:00:00.300000Z,101')}", "rel" => "previous" },
        ])
      end

      it "returns the correct list when going backwards" do
        get :index, params: { before: "2017-01-01T09:00:00.300000Z,111" }
        expect(parsed_response["results"].count).to eq(100)
        expect(parsed_response["results"].first["base_path"]).to eq("/content11")
        expect(parsed_response["results"].last["base_path"]).to eq("/content110")
        expect(parsed_response["links"]).to eq([
          { "href" => "http://test.host/v2/editions?after=#{u('2017-01-01T09:00:00.300000Z,110')}", "rel" => "next" },
          { "href" => "http://test.host/v2/editions?before=#{u('2017-01-01T09:00:00.300000Z,111')}", "rel" => "self" },
          { "href" => "http://test.host/v2/editions?before=#{u('2017-01-01T09:00:00.100000Z,11')}", "rel" => "previous" },
        ])
      end

      context "with a custom order" do
        it "returns the results in the expected order" do
          get :index, params: { order: "-updated_at" }
          expect(parsed_response["results"].first["base_path"]).to eq("/content150")
          expect(parsed_response["links"]).to eq([
            { "href" => "http://test.host/v2/editions?order=-updated_at&after=#{u('2017-01-01T09:00:00.200000Z,51')}", "rel" => "next" },
            { "href" => "http://test.host/v2/editions?order=-updated_at", "rel" => "self" },
          ])
        end
      end

      context "with a custom key" do
        it "returns the correct next page link" do
          get :index, params: { order: "created_at", after: "2017-01-01T09:00:00.100000Z,10" }
          expect(parsed_response["links"]).to eq([
            { "href" => "http://test.host/v2/editions?order=created_at&after=#{u('2017-01-01T09:00:00.300000Z,110')}", "rel" => "next" },
            { "href" => "http://test.host/v2/editions?after=#{u('2017-01-01T09:00:00.100000Z,10')}&order=created_at", "rel" => "self" },
            { "href" => "http://test.host/v2/editions?order=created_at&before=#{u('2017-01-01T09:00:00.100000Z,11')}", "rel" => "previous" },
          ])
        end
      end

      context "with a custom pagination count" do
        it "returns the correct number of results" do
          get :index, params: { per_page: 25 }
          expect(parsed_response["results"].count).to eq(25)
          expect(parsed_response["links"]).to eq([
            { "href" => "http://test.host/v2/editions?per_page=25&after=#{u('2017-01-01T09:00:00.100000Z,25')}", "rel" => "next" },
            { "href" => "http://test.host/v2/editions?per_page=25", "rel" => "self" },
          ])
        end

        it "returns the correct results for the second page" do
          get :index, params: { per_page: 25, after: "2017-01-01T09:00:00.100000Z,25" }
          expect(parsed_response["results"].count).to eq(25)
          expect(parsed_response["links"]).to eq([
            { "href" => "http://test.host/v2/editions?per_page=25&after=#{u('2017-01-01T09:00:00.100000Z,50')}", "rel" => "next" },
            { "href" => "http://test.host/v2/editions?after=#{u('2017-01-01T09:00:00.100000Z,25')}&per_page=25", "rel" => "self" },
            { "href" => "http://test.host/v2/editions?per_page=25&before=#{u('2017-01-01T09:00:00.100000Z,26')}", "rel" => "previous" },
          ])
        end
      end
    end

    context "filtered by state" do
      it "returns only published editions" do
        get :index, params: { states: %w(published) }
        expect(parsed_response["results"].count).to eq(50)
        expect(parsed_response["links"]).to eq([
          { "href" => "http://test.host/v2/editions?states%5B%5D=published", "rel" => "self" },
        ])
      end
    end

    context "filtered by locale" do
      it "returns only published editions" do
        get :index, params: { locale: "fr" }
        expect(parsed_response["results"].count).to eq(50)
        expect(parsed_response["links"]).to eq([
          { "href" => "http://test.host/v2/editions?locale=fr", "rel" => "self" },
        ])
      end
    end

    context "filtered by publishing app" do
      it "returns only published editions" do
        get :index, params: { publishing_app: "test" }
        expect(parsed_response["results"].count).to eq(50)
        expect(parsed_response["links"]).to eq([
          { "href" => "http://test.host/v2/editions?publishing_app=test", "rel" => "self" },
        ])
      end
    end

    context "outputting custom fields" do
      it "returns only the fields specified" do
        get :index, params: { fields: %w(content_id publishing_app) }
        expect(parsed_response["results"].first.keys)
          .to eq(%w(content_id publishing_app))
        expect(parsed_response["links"]).to eq([
          { "href" => "http://test.host/v2/editions?fields%5B%5D=content_id&fields%5B%5D=publishing_app&after=2017-01-01T09%3A00%3A00.200000Z%2C100", "rel" => "next" },
          { "href" => "http://test.host/v2/editions?fields%5B%5D=content_id&fields%5B%5D=publishing_app", "rel" => "self" },
        ])
      end
    end
  end
end