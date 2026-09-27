---
name: Test App in Agent
description: Edit main, run Rails specs in Docker, and propose tested changes as a draft PR.
intent: Make a requested code change, verify it with targeted and full Dockerized Rails specs, and push a reviewable branch.
on:
  workflow_dispatch:
    inputs:
      task:
        description: Code change to make and verify
        required: true
        type: string
checkout:
  ref: main
  fetch-depth: 0
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
      tools_dir=/tmp/gh-aw/test-app-tools
      mkdir -p /tmp/gh-aw/test-app-output
      docker_cli="$(readlink -f "$(command -v docker)")"
      compose_plugin="$(docker info --format '{{range .ClientInfo.Plugins}}{{if eq .Name "compose"}}{{.Path}}{{end}}{{end}}')"
      test -x "$docker_cli"
      test -x "$compose_plugin"
      install -Dm755 "$docker_cli" "$tools_dir/bin/docker"
      install -Dm755 "$compose_plugin" "$tools_dir/docker-config/cli-plugins/docker-compose"
      DOCKER_CONFIG="$tools_dir/docker-config" "$tools_dir/bin/docker" compose version
      cat > "$tools_dir/bin/request-pr" <<EOF
      #!/bin/sh
      export PATH="/usr/local/bin:/usr/bin:/bin\${PATH:+:\$PATH}"
      if [ "\$(cat /tmp/gh-aw/test-app-tools/full-suite-status 2>/dev/null)" != passed ]; then
        echo 'The full RSpec suite has not passed.' >&2
        exit 1
      fi
      exec "$RUNNER_TEMP/gh-aw/mcp-cli/bin/safeoutputs" create_pull_request "\$@"
      EOF
      chmod 755 "$tools_dir/bin/request-pr"
      echo "$tools_dir/bin" >> "$GITHUB_PATH"
      echo "DOCKER_CONFIG=$tools_dir/docker-config" >> "$GITHUB_ENV"
  - name: Build the Rails test image on the runner
    run: |
      set -euo pipefail
      seed_dir=/tmp/gh-aw/test-app-seed
      git clone --depth 1 --branch main "https://github.com/$GITHUB_REPOSITORY.git" "$seed_dir"
      git -C "$seed_dir" rev-parse HEAD > /tmp/gh-aw/test-app-tools/prebuilt-sha
      docker pull mysql:8.4
      docker compose -p app -f "$seed_dir/compose.yml" build test
      docker image inspect app-test >/dev/null
safe-outputs:
  report-failed-jobs: false
  report-failure-as-issue: false
  create-pull-request:
    base-branch: main
    draft: true
    fallback-as-issue: false
    if-no-changes: error
  noop:
    report-as-issue: false
post-steps:
  - name: Stop app test containers
    if: always()
    run: |
      if [ -x "$GITHUB_WORKSPACE/test-app" ]; then
        "$GITHUB_WORKSPACE/test-app" stop
      fi
  - name: Upload agent test results
    if: always()
    uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
    with:
      name: test-app-output
      path: |
        /tmp/gh-aw/test-app-output/test-app-result.txt
        /tmp/gh-aw/test-app-output/agent-changes.patch
      if-no-files-found: warn
      retention-days: 3
  - name: Require a passing full RSpec suite
    if: always()
    run: |
      if [ "$(cat /tmp/gh-aw/test-app-tools/full-suite-status 2>/dev/null)" != passed ]; then
        echo '::error::The agent did not complete a passing full RSpec suite.'
        exit 1
      fi
---

# Test App in Agent

The workflow checks out the latest `main` into the workspace root before you
start. Work only in that checkout. Record its commit SHA.
Check that SHA against `/tmp/gh-aw/test-app-tools/prebuilt-sha`. If they
differ, report that main moved after the image was built and stop before testing.
If they match, create and switch to a local `agent/test-app` branch before editing.

The requested change is: ${{ inputs.task }}

The Docker CLI and Compose plugin are staged in `/tmp/gh-aw/test-app-tools`
by a runner step. That step also builds the Rails test image and pulls MySQL on
the runner, where image downloads work. Your command environment may omit
`GITHUB_WORKSPACE` and shorten `PATH`; use the checked out `test-app` script for
container commands because it restores the system tool paths and Compose plugin
configuration. Use `docker info` and `docker compose version` inside your
sandbox before starting the tests, using `/tmp/gh-aw/test-app-tools/bin/docker`
if `docker` is absent from `PATH`. If either command fails, record the error
and do not claim the tests ran.

From the checkout, run `./test-app start --no-build` once to boot MySQL and the long-running
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
test results in `/tmp/gh-aw/test-app-output/test-app-result.txt`. From the checkout,
run `git add -N .`, then write `git diff --binary` to
`/tmp/gh-aw/test-app-output/agent-changes.patch` so new files are included in the
reviewable patch. Run `./test-app stop` when finished, including after
a test failure. A runner post-step uploads both output files as the
`test-app-output` artifact. After the full suite passes, if your code changes
are nonempty, stage the intended source and spec changes and make a local Git
commit. Then call `/tmp/gh-aw/test-app-tools/bin/request-pr` with
`--title`, `--body`, and `--branch agent/test-app` to request a draft pull
request. The separate safe output job pushes the branch and opens the PR. Do
not push directly or merge into `main`. If checkout or container startup fails,
record the error, create an empty patch, and avoid claiming tests ran.
