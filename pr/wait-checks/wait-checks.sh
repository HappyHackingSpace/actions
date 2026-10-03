#!/usr/bin/env bash
set -euo pipefail

deadline=$(( $(date +%s) + INPUT_TIMEOUT_MINUTES * 60 ))
own_run="/actions/runs/${GITHUB_RUN_ID}/"

while :; do
  # Jobs of the current run are excluded, otherwise this step would wait on itself.
  runs=$(gh api --paginate "repos/$INPUT_REPOSITORY/commits/$INPUT_SHA/check-runs?per_page=100" \
    --jq ".check_runs[] | select((.details_url // \"\") | contains(\"$own_run\") | not) | [.name, .status, (.conclusion // \"\")] | @tsv")
  statuses=$(gh api --paginate "repos/$INPUT_REPOSITORY/commits/$INPUT_SHA/status?per_page=100" \
    --jq '.statuses[] | [.context, .state] | @tsv')

  total=0 pending=0 failed=0
  while IFS=$'\t' read -r name status conclusion; do
    [[ -z "$name" ]] && continue
    total=$((total + 1))
    if [[ "$status" != "completed" ]]; then
      pending=$((pending + 1))
    elif [[ ! "$conclusion" =~ ^(success|skipped|neutral)$ ]]; then
      failed=$((failed + 1)); echo "::error::check '$name' concluded $conclusion"
    fi
  done <<< "$runs"
  while IFS=$'\t' read -r context state; do
    [[ -z "$context" ]] && continue
    total=$((total + 1))
    case "$state" in
      success) ;;
      pending) pending=$((pending + 1)) ;;
      *) failed=$((failed + 1)); echo "::error::status '$context' is $state" ;;
    esac
  done <<< "$statuses"

  (( failed > 0 )) && exit 1
  if (( pending == 0 )); then
    if (( total == 0 )) && [[ "$INPUT_REQUIRE_CHECKS" == "true" ]]; then
      echo "::notice::no checks verify this update, leaving it for review"
      exit 1
    fi
    echo "all $total checks passed"
    exit 0
  fi
  if (( $(date +%s) >= deadline )); then
    echo "::error::timed out with $pending checks pending"
    exit 1
  fi
  echo "waiting on $pending of $total checks"
  sleep "$INPUT_INTERVAL_SECONDS"
done
