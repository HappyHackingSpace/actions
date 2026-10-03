#!/usr/bin/env bash
set -euo pipefail

files() {
  find . \( -name node_modules -o -name vendor -o -name .venv -o -name .git \) -prune -o -type f \( "$@" \) -print | sort
}

dirs() {
  files "$@" | xargs -r -n1 dirname | sort -u
}

has_script() {
  node -e 'const s = require("./package.json").scripts || {}; const v = s[process.argv[1]];
    process.exit(v && !/no test specified/.test(v) ? 0 : 1)' "$1"
}

check_node() {
  local projects
  projects=$(dirs -name package-lock.json -o -name npm-shrinkwrap.json -o -name pnpm-lock.yaml -o -name yarn.lock -o -name bun.lock -o -name bun.lockb)
  # Lockfile-less repos: check top-level packages only, nested ones are usually workspaces of them.
  [[ -z "$projects" ]] && projects=$(dirs -name package.json | awk 'NR == 1 || index($0, prev "/") != 1 { print; prev = $0 }')
  for dir in $projects; do
    echo "::group::node $dir"
    pushd "$dir" > /dev/null
    local run=(npm run)
    if [[ -f pnpm-lock.yaml ]]; then
      npm install -g corepack && corepack enable
      pnpm install --frozen-lockfile; run=(pnpm run)
    elif [[ -f yarn.lock ]]; then
      npm install -g corepack && corepack enable
      if [[ -f .yarnrc.yml ]]; then yarn install --immutable; else yarn install --frozen-lockfile; fi
      run=(yarn run)
    elif [[ -f bun.lock || -f bun.lockb ]]; then
      npm install -g bun
      bun install --frozen-lockfile; run=(bun run)
    elif [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
      npm ci
    else
      npm install
    fi
    for script in build test; do
      if has_script "$script"; then "${run[@]}" "$script"; fi
    done
    popd > /dev/null
    echo "::endgroup::"
  done
}

check_go() {
  for dir in $(dirs -name go.mod); do
    echo "::group::go $dir"
    (cd "$dir" && go mod download && go build ./... && go test ./...)
    echo "::endgroup::"
  done
}

run_pytest() {
  "$@" python -c 'import pytest' 2> /dev/null || return 0
  # Exit code 5 means no tests were collected, which is not a compatibility failure.
  "$@" python -m pytest -q || [[ $? -eq 5 ]]
}

check_uv() {
  for dir in $(dirs -name uv.lock); do
    echo "::group::uv $dir"
    (cd "$dir" && uv sync --locked --all-extras && run_pytest uv run --no-sync)
    echo "::endgroup::"
  done
}

check_pip() {
  for dir in $(dirs -name 'requirements*.txt' -o -name pyproject.toml -o -name setup.py -o -name Pipfile); do
    [[ -f "$dir/uv.lock" ]] && continue
    echo "::group::pip $dir"
    (
      cd "$dir"
      python -m venv "$RUNNER_TEMP/venv-${dir//\//_}"
      # shellcheck source=/dev/null
      source "$RUNNER_TEMP/venv-${dir//\//_}/bin/activate"
      python -m pip install -q --upgrade pip
      for req in requirements*.txt; do [[ -f "$req" ]] && pip install -r "$req"; done
      [[ -f Pipfile ]] && pip install -q pipenv && pipenv install --system --deploy
      if [[ -f setup.py ]] || grep -q '^\[project\]' pyproject.toml 2> /dev/null; then pip install .; fi
      run_pytest
    )
    echo "::endgroup::"
  done
}

check_docker() {
  for file in $(files -name 'Dockerfile*' ! -name '*.dockerignore'); do
    echo "::group::docker $file"
    # Some Dockerfiles expect the repository root as build context rather than their own directory.
    docker build --pull -f "$file" "$(dirname "$file")" || docker build --pull -f "$file" .
    echo "::endgroup::"
  done
}

check_docker_compose() {
  for file in $(files -name 'compose*.y*ml' -o -name 'docker-compose*.y*ml'); do
    echo "::group::compose $file"
    docker compose -f "$file" config -q
    docker compose -f "$file" pull --ignore-buildable --quiet
    echo "::endgroup::"
  done
}

case "$INPUT_ECOSYSTEM" in
  npm_and_yarn|bun) check_node ;;
  go_modules) check_go ;;
  uv) check_uv ;;
  pip) check_pip ;;
  docker) check_docker ;;
  docker_compose) check_docker_compose ;;
esac
