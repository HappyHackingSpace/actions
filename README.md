# HappyHackingSpace Actions

Shared GitHub Actions for HappyHackingSpace repositories.

## Dependabot auto-merge

Merges patch and minor Dependabot updates once nothing breaks. Majors are left for review.

```yaml
name: Dependabot

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  checks: read
  contents: write
  pull-requests: write
  statuses: read

jobs:
  auto-merge:
    if: github.event.pull_request.user.login == 'dependabot[bot]'
    uses: HappyHackingSpace/actions/.github/workflows/dependabot-auto-merge.yaml@v1
```

A PR is merged only when:

1. the update is not a semver major,
2. [`dependabot/compat-checks`](dependabot/compat-checks) passes: it installs, builds and tests every project of the updated ecosystem (npm, pnpm, yarn, bun, Go, pip, uv, Docker, Compose),
3. [`pr/wait-checks`](pr/wait-checks) sees every other check on the PR pass. For ecosystems without a compat check (GitHub Actions, Gradle, NuGet, Swift, ...) at least one such check must exist.

Merges use `GITHUB_TOKEN`, so they do not trigger `push` workflows.
