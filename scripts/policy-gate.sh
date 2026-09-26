#!/usr/bin/env bash
# Policy Gate (REVIEW_PROTOCOL §10): decide whether a pull request may be merged automatically.
#   policy-gate.sh --state <pr-state output> --paths <file> --checks <check-runs.json>
#       --base-tip <sha> [--root <project-root>]
# --paths holds the files the pull request changes, NUL-separated, as printed by
# `git diff --no-renames --name-only -z <base>...<head>`; --checks is GitHub's check-runs response
# for the head commit; --base-tip is the current tip of the base branch, whose commit must be in
# the local repository. Nothing is read from the network and nothing from the pull request runs.
# Output is key=value lines; the first is decision=:
#   AUTO_MERGE_ALLOWED   exit 0   every condition holds
#   NOT_READY            exit 10  not yet: the head is not reviewed or VERIFIED, does not contain the
#                                 current base, or CI is not green
#   HUMAN_GATE_REQUIRED  exit 20  the owner decides; automation never merges this pull request
# Exit 2 is invalid input or configuration. Every condition is required, so a condition that
# cannot be established never ends in AUTO_MERGE_ALLOWED.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

usage_error() { echo "$*" >&2; exit 2; }

state_file="" paths_file="" checks_file="" base_tip="" ROOT=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage_error "missing value for $1"
  case "$1" in
    --state) state_file="$2" ;;
    --paths) paths_file="$2" ;;
    --checks) checks_file="$2" ;;
    --base-tip) base_tip="$2" ;;
    --root) ROOT="$2" ;;
    *) usage_error "unknown argument: $1" ;;
  esac
  shift 2
done
command -v jq >/dev/null 2>&1 || usage_error "policy-gate.sh needs jq"
for f in "$state_file" "$paths_file" "$checks_file"; do
  [ -n "$f" ] && [ -f "$f" ] || usage_error "--state, --paths and --checks must name existing files"
done
printf '%s\n' "$base_tip" | grep -qE '^[0-9a-f]{40}$' || usage_error "--base-tip must be a 40-character sha"
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
git -C "$ROOT" cat-file -e "$base_tip^{commit}" 2>/dev/null || usage_error "base tip $base_tip is not in $ROOT"
profile="$ROOT/.ai-collab/project.yaml"
[ -f "$profile" ] || usage_error "$profile missing"

# A list the parser cannot read is an error, never an empty list: an empty list merges more.
read_list() {
  local out rc
  out="$(aick_profile_list "$profile" "$1" "$2")"; rc=$?
  case "$rc" in
    0) printf '%s\n' "$out" ;;
    1) usage_error "project.yaml: $1.$2 is missing; automatic merge stays off (REVIEW_PROTOCOL §10)" ;;
    *) usage_error "project.yaml: $1.$2 must be [] or a list of '- <value>' lines" ;;
  esac
}
project_paths="$(read_list policy_gate human_paths)" || exit 2
required="$(read_list auto_merge required_checks)" || exit 2
[ -n "$required" ] || usage_error "project.yaml: auto_merge.required_checks lists no checks; automatic merge needs CI (REVIEW_PROTOCOL §10)"

state() { sed -n "s/^$1=//p" "$state_file" | tail -n 1; }
head="$(state pr_head)"
printf '%s\n' "$head" | grep -qE '^[0-9a-f]{40}$' || usage_error "state has no valid pr_head"
jq -e '.check_runs | type == "array"' "$checks_file" >/dev/null 2>&1 || usage_error "--checks is not a check-runs response"

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
detail=""
add_detail() { detail="$detail$1
"; }
decide() {
  printf 'decision=%s\nreason=%s\n' "$1" "$2"
  printf '%s' "$detail"
  printf 'head=%s\n' "$head"
  case "$1" in AUTO_MERGE_ALLOWED) exit 0 ;; NOT_READY) exit 10 ;; *) exit 20 ;; esac
}

# 1. Only an open, ready, same-repository pull request into the default branch is delivered.
[ "$(state same_repo)" = true ] || decide NOT_READY fork
[ "$(state pr_state)" = open ] || decide NOT_READY pr_not_open
[ "$(state pr_draft)" = false ] || decide NOT_READY draft
[ -n "$(state default_branch)" ] && [ "$(state pr_base_ref)" = "$(state default_branch)" ] \
  || decide NOT_READY not_default_branch

# 2. The Loop Guard stopped the review loop.
if [ "$(state decision)" = HUMAN_GATE_REQUIRED ]; then
  add_detail "loop_guard_reason=$(state reason)"
  decide HUMAN_GATE_REQUIRED loop_guard
fi

# 3. The Reviewer App's latest record at this exact head must be VERIFIED.
case "$(state head_review)" in
  VERIFIED) ;;
  CHANGES_REQUESTED) decide NOT_READY changes_requested ;;
  *) decide NOT_READY not_reviewed ;;
esac

# 4. High-risk changes go to the owner: paths from project.yaml and the built-in list, and any
# risk flag the Reviewer set. Paths are compared in lower case, and renames are listed as a
# deletion plus an addition, so moving a protected file still names the protected path.
patterns=""
for p in "${AICK_POLICY_BUILTIN_PATHS[@]}"; do patterns="$patterns$(lower "$p")
"; done
patterns="$patterns$(lower "$project_paths")"
protected=""
while IFS= read -r -d '' path; do
  lp="$(lower "$path")"
  while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    # shellcheck disable=SC2254 # the pattern is a glob on purpose
    case "$lp" in $pattern) protected="$protected$path
"; break ;; esac
  done <<EOF_PATTERNS
$patterns
EOF_PATTERNS
done < "$paths_file"
flags="$(state head_risk_flags)"
[ -z "$protected" ] || add_detail "protected_paths=$(printf '%s' "$protected" | head -n 20 | paste -sd, -)"
[ -z "$flags" ] || add_detail "risk_flags=$flags"
[ -z "$protected" ] || decide HUMAN_GATE_REQUIRED protected_path
[ -z "$flags" ] || decide HUMAN_GATE_REQUIRED reviewer_risk_flags

# 5. The head must already contain the current base, so the CI run on the head tested exactly the
# tree that the merge delivers. Otherwise two pull requests that were each green on an older base
# could be merged together without their combination ever being tested.
git -C "$ROOT" merge-base --is-ancestor "$base_tip" "$head" 2>/dev/null || {
  add_detail "base_tip=$base_tip"
  decide NOT_READY base_outdated
}

# 6. Every required check has a successful GitHub Actions run on this head. Runs from any other
# app, or for another commit, do not count.
failed="" pending=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  run="$(aick_required_check "$checks_file" "$name" "$head")"
  if [ -z "$run" ] || [ "$(printf '%s' "$run" | jq -r .status)" != completed ]; then
    pending="$pending$name
"
  elif [ "$(printf '%s' "$run" | jq -r .conclusion)" != success ]; then
    failed="$failed$name
"
  fi
done <<EOF_REQUIRED
$required
EOF_REQUIRED
if [ -n "$failed" ]; then
  add_detail "failed_checks=$(printf '%s' "$failed" | paste -sd, -)"
  decide NOT_READY ci_failed
fi
if [ -n "$pending" ]; then
  add_detail "pending_checks=$(printf '%s' "$pending" | paste -sd, -)"
  decide NOT_READY ci_pending
fi

decide AUTO_MERGE_ALLOWED all_conditions_met
