class CreatePostReactions < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :likes_count, :integer, null: false, default: 0
    add_column :posts, :dislikes_count, :integer, null: false, default: 0

    create_table :post_reactions do |t|
      t.references :post, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :kind, null: false

      t.timestamps
    end

    add_index :post_reactions, [ :post_id, :user_id ], unique: true
    add_index :post_reactions, [ :post_id, :kind ]
  end
end
