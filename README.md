# GitHub workflow playground

A small Rails API for exercising GitHub Actions with a real MySQL test database.

## Run the specs

With Docker Compose installed, run:

```sh
./test-app
```

You can invoke the script from any directory; it changes to the repository root.
The script starts MySQL and the Rails test container, runs the full RSpec suite,
returns its exit status, and stops the containers. The same command works in CI.

To keep the containers running while editing code and run a selected spec:

```sh
./test-app start
./test-app rspec spec/requests/notes_spec.rb:5
./test-app rspec
./test-app stop
```

The checkout is mounted into the Rails container, so code and spec edits appear
there immediately. Run `./test-app start` again after changing dependencies to
rebuild the image.

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
