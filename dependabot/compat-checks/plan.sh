#!/usr/bin/env bash
set -euo pipefail

first() {
  find . \( -name node_modules -o -name vendor -o -name .venv -o -name .git \) -prune -o -type f \( "$@" \) -print \
    | awk -F/ '{ print NF "\t" $0 }' | sort -n | cut -f2 | head -1
}

checked=true
case "$INPUT_ECOSYSTEM" in
  npm_and_yarn|bun) echo "node-version-file=$(first -name .nvmrc -o -name .node-version)" >> "$GITHUB_OUTPUT" ;;
  go_modules) echo "go-version-file=$(first -name go.mod)" >> "$GITHUB_OUTPUT" ;;
  pip|uv) echo "python-version-file=$(first -name .python-version)" >> "$GITHUB_OUTPUT" ;;
  docker|docker_compose) ;;
  *) checked=false; echo "::notice::no compatibility check for $INPUT_ECOSYSTEM, relying on the repository's own checks" ;;
esac
echo "checked=$checked" >> "$GITHUB_OUTPUT"
