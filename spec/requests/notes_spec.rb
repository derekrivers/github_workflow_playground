require "rails_helper"

RSpec.describe "Notes API", type: :request do
  describe "GET /notes" do
    it "returns notes in creation order" do
      first = Note.create!(title: "First", body: "One")
      second = Note.create!(title: "Second", body: "Two")

      get "/notes"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([
        { "id" => first.id, "title" => "First", "body" => "One" },
        { "id" => second.id, "title" => "Second", "body" => "Two" }
      ])
    end
  end

  describe "GET /notes/:id" do
    it "returns one note" do
      note = Note.create!(title: "Example", body: "Details")

      get "/notes/#{note.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "id" => note.id, "title" => "Example", "body" => "Details"
      )
    end
  end

  describe "POST /notes" do
    it "creates a note" do
      expect do
        post "/notes", params: { note: { title: "New", body: "Text" } }, as: :json
      end.to change(Note, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include("title" => "New", "body" => "Text")
    end

    it "rejects a note without a title" do
      expect do
        post "/notes", params: { note: { title: "", body: "Text" } }, as: :json
      end.not_to change(Note, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.fetch("errors")).to include("Title can't be blank")
    end
  end
end
