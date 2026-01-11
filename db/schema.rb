# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_01_11_225914) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "actors", force: :cascade do |t|
    t.string "github_id", null: false
    t.string "login", null: false
    t.string "avatar_url"
    t.jsonb "raw_data", null: false
    t.datetime "fetched_at", precision: nil, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["github_id"], name: "index_actors_on_github_id", unique: true
    t.index ["login"], name: "index_actors_on_login"
    t.index ["raw_data"], name: "index_actors_on_raw_data", using: :gin
  end

  create_table "github_events", force: :cascade do |t|
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.jsonb "raw_payload"
    t.datetime "ingested_at", precision: nil, null: false
    t.datetime "processed_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "s3_key"
    t.index ["event_id"], name: "index_github_events_on_event_id", unique: true
    t.index ["event_type"], name: "index_github_events_on_event_type"
    t.index ["raw_payload"], name: "index_github_events_on_raw_payload", using: :gin
    t.index ["s3_key"], name: "index_github_events_on_s3_key"
  end

  create_table "job_states", force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_job_states_on_key", unique: true
  end

  create_table "push_events", force: :cascade do |t|
    t.bigint "github_event_id", null: false
    t.string "repository_id", null: false
    t.string "push_id", null: false
    t.string "ref", null: false
    t.string "head", null: false
    t.string "before", null: false
    t.bigint "actor_id"
    t.bigint "enriched_repository_id"
    t.string "enrichment_status", default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_push_events_on_actor_id"
    t.index ["enriched_repository_id"], name: "index_push_events_on_enriched_repository_id"
    t.index ["enrichment_status"], name: "index_push_events_on_enrichment_status"
    t.index ["github_event_id"], name: "index_push_events_on_github_event_id"
    t.index ["push_id"], name: "index_push_events_on_push_id", unique: true
    t.index ["repository_id", "created_at"], name: "index_push_events_on_repository_id_and_created_at"
    t.index ["repository_id"], name: "index_push_events_on_repository_id"
  end

  create_table "repositories", force: :cascade do |t|
    t.string "github_id", null: false
    t.string "full_name", null: false
    t.text "description"
    t.jsonb "raw_data", null: false
    t.datetime "fetched_at", precision: nil, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["full_name"], name: "index_repositories_on_full_name"
    t.index ["github_id"], name: "index_repositories_on_github_id", unique: true
    t.index ["raw_data"], name: "index_repositories_on_raw_data", using: :gin
  end

  add_foreign_key "push_events", "actors"
  add_foreign_key "push_events", "github_events"
  add_foreign_key "push_events", "repositories", column: "enriched_repository_id"
end
