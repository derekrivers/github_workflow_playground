# GitHub workflow playground

A small Rails API for exercising GitHub Actions with a real MySQL test database.

## Run the specs

With Docker Compose installed, run:

```sh
./test-app
```

You can invoke the script from any directory; it changes to the repository root.
The `test` container prepares the database and runs the request specs. The script
returns the RSpec exit status, so the same command works in CI. To remove the
containers and test database after a run:

```sh
docker compose down -v
```

The [Rails tests workflow](.github/workflows/rails-tests.yml) runs this command
on pushes and pull requests.

## API

| Method | Path | Result |
| --- | --- | --- |
| `GET` | `/notes` | List notes in creation order |
| `GET` | `/notes/:id` | Show one note |
| `POST` | `/notes` | Create a note from JSON such as `{"note":{"title":"Hello","body":"World"}}` |

The `notes` table has a required `title` and an optional `body`.

For local Ruby development, use Ruby 3.2 and MySQL, run `bundle install`, set
`DB_HOST`, `DB_USER`, and `DB_PASSWORD` as needed, then run:

```sh
RAILS_ENV=test bin/rails db:prepare
RAILS_ENV=test bundle exec rspec
```
