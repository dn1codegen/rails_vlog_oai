class AddTagsToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :tags, :string, null: false, default: ""
    add_index :posts, :tags
  end
end
