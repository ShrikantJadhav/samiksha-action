#!/usr/bin/env bash
# Run Samiksha, write the review to the step summary, optionally comment on the
# PR, and enforce a verdict floor when requested.
set -euo pipefail

export SAMIKSHA_MODEL="${INPUT_MODEL:-${SAMIKSHA_MODEL:-${OPENAI_MODEL:-}}}"
export SAMIKSHA_BASE_URL="${INPUT_BASE_URL:-${SAMIKSHA_BASE_URL:-${OPENAI_BASE_URL:-${OPENAI_API_BASE:-}}}}"
export SAMIKSHA_API_KEY="${INPUT_API_KEY:-${SAMIKSHA_API_KEY:-${OPENAI_API_KEY:-}}}"

if [[ -z "$SAMIKSHA_MODEL" ]]; then
  echo "::error::samiksha-action needs a model: set 'model' or SAMIKSHA_MODEL / OPENAI_MODEL"
  exit 2
fi

upper() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

rank() {
  case "$(upper "$1")" in
    SOUND) echo 0 ;;
    CONCERNS) echo 1 ;;
    UNSOUND) echo 2 ;;
    *) echo 99 ;;
  esac
}

set_output() {
  echo "$1=$2" >> "$GITHUB_OUTPUT"
}

review="$RUNNER_TEMP/samiksha-review.md"
intent="${INPUT_INTENT:-${PR_TITLE:-}}"

args=(review --blast "$BLAST_BIN" --pass-steps "${PASS_STEPS:-3}")
if [[ -n "${BASE:-}" ]]; then args+=(--base "$BASE"); fi
if [[ -n "$intent" ]]; then args+=(--intent "$intent"); fi
if [[ "${ALLOW_RUN:-false}" == "true" ]]; then args+=(--allow-run); fi
if [[ "${SHOW_PASSES:-false}" == "true" ]]; then args+=(--show-passes); fi
if [[ "${SINGLE_AGENT:-false}" == "true" ]]; then args+=(--single-agent); fi

set +e
samiksha "${args[@]}" > "$review"
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  echo "::error::samiksha review failed with exit code $rc"
  cat "$review" >&2
  exit "$rc"
fi

if grep -q '^samiksha: no changes detected' "$review"; then
  set_output verdict NO_CHANGES
  set_output review_path "$review"
  set_output failed false
  echo "::notice::Samiksha: no changes detected"
  {
    echo
    echo "### Samiksha review"
    echo
    echo "_No changes detected._"
  } >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

verdict="$(sed -n 's/^## Verdict:[[:space:]]*\([A-Za-z]*\).*$/\1/p' "$review" | head -n 1 | tr '[:lower:]' '[:upper:]')"
if [[ -z "$verdict" ]]; then
  verdict=UNKNOWN
  echo "::warning::Could not parse a verdict from the Samiksha review"
fi

{
  echo
  echo "### Samiksha review"
  echo
  echo "- Verdict: **$verdict**"
  if [[ -n "$intent" ]]; then
    echo "- Intent: $(printf '%s' "$intent" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
  fi
  echo
  echo "<details><summary>Full evidence-backed review</summary>"
  echo
  cat "$review"
  echo
  echo "</details>"
} >> "$GITHUB_STEP_SUMMARY"

if [[ "${DO_COMMENT:-false}" == "true" ]]; then
  if [[ -z "${PR_NUMBER:-}" ]]; then
    echo "::warning::comment: true only works on pull_request events"
  else
    if gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body-file "$review"; then
      echo "Posted review as PR comment."
    else
      echo "::warning::Could not post the PR comment; check pull-requests: write permission"
    fi
  fi
fi

failed=false
if [[ -n "${FAIL_ON:-}" ]]; then
  threshold="$(upper "$FAIL_ON")"
  threshold_rank="$(rank "$threshold")"
  verdict_rank="$(rank "$verdict")"
  if [[ "$threshold_rank" -eq 99 ]]; then
    echo "::error::Invalid fail-on-verdict '$FAIL_ON' (want SOUND, CONCERNS, or UNSOUND)"
    exit 2
  fi
  if [[ "$verdict_rank" -eq 99 || "$verdict_rank" -ge "$threshold_rank" ]]; then
    failed=true
  fi
fi

set_output verdict "$verdict"
set_output review_path "$review"
set_output failed "$failed"

if [[ "$failed" == "true" ]]; then
  echo "::error::Samiksha verdict $verdict met fail-on threshold $threshold"
  exit 1
fi

echo "::notice::Samiksha verdict: $verdict"
