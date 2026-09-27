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
---

# Test App in Agent

Clone the latest `main` commit with `git clone --depth 1 --branch main
https://github.com/${{ github.repository }}.git "$GITHUB_WORKSPACE/app"` from inside
your sandbox. Work only in that clone. Record its commit SHA.

The requested change is: ${{ inputs.task }}

The Docker CLI and Compose plugin are staged in `$GITHUB_WORKSPACE/.agent-tools`
by a runner step. Use `docker info` and `docker compose version` inside your
sandbox before starting the tests. If either command fails, record the error
and do not claim the tests ran.

From the clone, run `./test-app start` once to boot MySQL and the long-running
Rails test container. The checkout is bind-mounted into `/app`, so source and
spec edits are visible inside the container immediately. Run
`./test-app rspec spec/requests/notes_spec.rb` as a baseline, then edit the
files needed for the requested change. After each edit, run the relevant specs
with `./test-app rspec <spec path>`, optionally including an RSpec line number.
Before finishing, run `./test-app rspec` for the full suite. If Gemfile or
Gemfile.lock changes, run `./test-app start` again to rebuild the image.

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
