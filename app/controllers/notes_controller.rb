class NotesController < ApplicationController
  def index
    render json: Note.order(:id).as_json(only: %i[id title body])
  end

  def show
    render json: Note.find(params[:id]).as_json(only: %i[id title body])
  end

  def create
    note = Note.new(note_params)

    if note.save
      render json: note.as_json(only: %i[id title body]), status: :created
    else
      render json: { errors: note.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def note_params
    params.require(:note).permit(:title, :body)
  end
end
