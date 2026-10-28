ActiveRecord::Schema[7.1].define(version: 2024_01_01_000000) do
  create_table "posts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "author_id"
    t.uuid "editor_uuid"
  end
  create_table "users", force: :cascade do |t|
    t.uuid "uuid"
  end
  create_table "staff", force: :cascade do |t|
    t.integer "manager_id"
  end
  create_table "comments", id: :uuid, force: :cascade do |t|
    t.references "commentable", polymorphic: true, type: :uuid
  end
end
