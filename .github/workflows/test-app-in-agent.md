---
name: Test App in Agent
description: Edit a fresh main clone while running selected Rails specs in Docker.
intent: Make a requested code change in a fresh main clone and verify it with targeted Dockerized Rails specs.
on:
  workflow_dispatch:
    inputs:
      task:
        description: Code change to make and verify
        required: true
        type: string
checkout: false
timeout-minutes: 60
concurrency:
  job-discriminator: ${{ github.run_id }}
permissions:
  contents: read
engine: codex
sandbox:
  agent:
    id: awf
    # AWF hides this socket by default; this grants the agent Docker daemon access.
    mounts:
      - /var/run/docker.sock:/var/run/docker.sock:rw
network:
  allowed:
    - defaults
    - github
    - containers
    - ruby
    - linux-distros
pre-agent-steps:
  - name: Stage Docker CLI and Compose for the agent
    run: |
      set -euo pipefail
      tools_dir="$GITHUB_WORKSPACE/.agent-tools"
      docker_cli="$(readlink -f "$(command -v docker)")"
      compose_plugin="$(docker info --format '{{range .ClientInfo.Plugins}}{{if eq .Name "compose"}}{{.Path}}{{end}}{{end}}')"
      test -x "$docker_cli"
      test -x "$compose_plugin"
      install -Dm755 "$docker_cli" "$tools_dir/bin/docker"
      install -Dm755 "$compose_plugin" "$tools_dir/docker-config/cli-plugins/docker-compose"
      DOCKER_CONFIG="$tools_dir/docker-config" "$tools_dir/bin/docker" compose version
      echo "$tools_dir/bin" >> "$GITHUB_PATH"
      echo "DOCKER_CONFIG=$tools_dir/docker-config" >> "$GITHUB_ENV"
  - name: Build the Rails test image on the runner
    run: |
      set -euo pipefail
      seed_dir="$GITHUB_WORKSPACE/.seed-app"
      git clone --depth 1 --branch main "https://github.com/$GITHUB_REPOSITORY.git" "$seed_dir"
      git -C "$seed_dir" rev-parse HEAD > "$GITHUB_WORKSPACE/.agent-tools/prebuilt-sha"
      docker pull mysql:8.4
      docker compose -p app -f "$seed_dir/compose.yml" build test
      docker image inspect app-test >/dev/null
safe-outputs:
  report-failed-jobs: false
  report-failure-as-issue: false
  upload-artifact:
    max-uploads: 1
    retention-days: 3
    max-size-bytes: 10485760
    allowed-paths:
      - output/test-app-result.txt
      - output/agent-changes.patch
  noop:
    report-as-issue: false
post-steps:
  - name: Stop app test containers
    if: always()
    run: |
      if [ -x "$GITHUB_WORKSPACE/app/test-app" ]; then
        "$GITHUB_WORKSPACE/app/test-app" stop
      fi
  - name: Require a passing full RSpec suite
    if: always()
    run: |
      if [ "$(cat "$GITHUB_WORKSPACE/.agent-tools/full-suite-status" 2>/dev/null)" != passed ]; then
        echo '::error::The agent did not complete a passing full RSpec suite.'
        exit 1
      fi
---

# Test App in Agent

Clone the latest `main` commit with `git clone --depth 1 --branch main
https://github.com/${{ github.repository }}.git "$GITHUB_WORKSPACE/app"` from inside
your sandbox. Work only in that clone. Record its commit SHA.
From the clone, check that SHA against `../.agent-tools/prebuilt-sha`. If they
differ, report that main moved after the image was built and stop before testing.

The requested change is: ${{ inputs.task }}

The Docker CLI and Compose plugin are staged in `$GITHUB_WORKSPACE/.agent-tools`
by a runner step. That step also builds the Rails test image and pulls MySQL on
the runner, where image downloads work. Your command environment may omit
`GITHUB_WORKSPACE` and shorten `PATH`; use the cloned `test-app` script for
container commands because it restores the system tool paths and Compose plugin
configuration. Use `docker info` and `docker compose version` inside your
sandbox before starting the tests. If either command fails, record the error
and do not claim the tests ran.

From the clone, run `./test-app start --no-build` once to boot MySQL and the long-running
Rails test container. The checkout is bind-mounted into `/app`, so source and
spec edits are visible inside the container immediately. Run
`./test-app rspec spec/requests/notes_spec.rb` as a baseline, then edit the
files needed for the requested change. After each edit, run the relevant specs
with `./test-app rspec <spec path>`, optionally including an RSpec line number.
Before finishing, run `./test-app rspec` for the full suite. The prebuilt image
matches the initial main commit; if Gemfile or Gemfile.lock changes, record that
the image needs rebuilding on the runner before the changed dependencies can be
tested. A passing full suite is required for the workflow job to succeed.

Record the commit SHA, commands, exit statuses, and a concise account of the
test results in `$GITHUB_WORKSPACE/output/test-app-result.txt`. From the clone,
run `git add -N .`, then write `git diff --binary` to
`$GITHUB_WORKSPACE/output/agent-changes.patch` so new files are included in the
reviewable patch. Run `./test-app stop` when finished, including after
a test failure. Upload both output files with the configured `upload-artifact`
safe output and summarize the result. If cloning or container startup fails,
record the error, create an empty patch, upload the report, and avoid claiming
tests ran. If no
artifact can be produced, call `noop` once with the reason. Do not create an
issue or push changes.
