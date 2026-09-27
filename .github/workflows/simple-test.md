---
name: Simple Test
on:
  workflow_dispatch:
    inputs:
      issue_number:
        description: Issue number to comment on
        required: true
        type: number

concurrency:
  job-discriminator: ${{ github.run_id }}

safe-outputs:
  add-comment:
    target: ${{ inputs.issue_number }}
    max: 1

engine: codex
---

# Simple Test

Read issue #${{ inputs.issue_number }} and its title and description. Add one
short, friendly comment acknowledging the issue and summarizing what was reported.
