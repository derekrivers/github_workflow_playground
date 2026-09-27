class CreateNotes < ActiveRecord::Migration[7.1]
  def change
    create_table :notes do |table|
      table.string :title, null: false
      table.text :body
      table.timestamps
    end
  end
end
