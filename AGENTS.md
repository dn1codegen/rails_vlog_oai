# Repository Guidelines

## Project Structure & Module Organization
This is a Rails 8 app. Core backend code lives in `app/`:
- `app/models` for domain entities (`Post`, `Comment`, `PostReaction`, `User`)
- `app/controllers` for HTTP endpoints (including namespaced `app/controllers/posts/reactions_controller.rb`)
- `app/services` for media/codec logic (`VideoCodecInspector`, `VideoThumbnailGenerator`, `MediaStreamInspector`)
- `app/jobs` for background work (`GeneratePostThumbnailJob`)

Frontend behavior uses Importmap + Hotwire in `app/javascript/controllers`. Database changes go in `db/migrate`; schema snapshots are in `db/schema.rb` plus `db/cache_schema.rb`, `db/queue_schema.rb`, and `db/cable_schema.rb`.

## Build, Test, and Development Commands
- `bin/setup --skip-server` installs gems, prepares DB, and clears temp/logs.
- `bin/dev` (or `bin/rails server`) starts the app on `http://localhost:3000`.
- `bin/rails db:prepare` creates/migrates local databases.
- `bin/rails test` runs Minitest suites.
- `bin/rubocop` runs style checks.
- `bin/ci` runs the local CI pipeline: setup, RuboCop, security audits, tests, and seed replant.

## Coding Style & Naming Conventions
Use RuboCop Rails Omakase (`.rubocop.yml`) as the source of truth. Follow standard Ruby/Rails conventions: 2-space indentation, `snake_case` methods/files, `CamelCase` classes/modules, plural controller names, and RESTful actions. Keep controllers thin; put reusable logic in models/services.

## Testing Guidelines
Tests use Minitest with fixtures in `test/fixtures`. Name files as `*_test.rb` and mirror app structure (for example, `app/models/post.rb` -> `test/models/post_test.rb`). Prefer:
- model tests for validations/business rules
- integration tests for auth and end-to-end flows (`test/integration/vlog_flow_test.rb`)

Run focused tests with commands like `bin/rails test test/models/post_test.rb`.

## Commit & Pull Request Guidelines
Recent commits favor short imperative subjects (for example, `Add reactions with counters...`). Keep commit titles specific and avoid vague messages like `update`. For PRs, include:
- purpose and behavior changes
- linked issue/task
- commands run (`bin/rubocop`, `bin/rails test`, `bin/ci` when relevant)
- screenshots for UI-visible changes

## Security & Configuration Tips
Video validation/preview features depend on FFmpeg tools:
- codec checks use `ffprobe`
- thumbnail generation uses `ffmpeg`

Use `REQUIRE_FFPROBE` and `THUMBNAIL_SYNC` to control behavior by environment.
