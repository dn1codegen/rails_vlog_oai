class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.string :title, null: false
      t.text :description

      t.timestamps
    end

    add_index :posts, :created_at
  end
end
