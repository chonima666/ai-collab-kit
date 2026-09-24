#!/usr/bin/env bash
# Rebuild a pull request's Loop Guard state from GitHub and judge it with verify.sh review-state.
#   pr-state.sh --repo <owner/repo> --pr <n> [--save-dir <dir>] [--root <project-root>]
#   pr-state.sh --pr-file <pr.json> --comments-file <comments.json> [--reviews-file <reviews.json>]
#       [--save-dir <dir>] [--root <project-root>]
# The first form reads the GitHub REST API with $GITHUB_TOKEN (read access is enough); the
# second reads saved API responses. Records count only when their author is the identity that
# owns them in project.yaml (REVIEW_PROTOCOL §9.6), so the three identities must be set and
# distinct. The PR description never counts as review state. Output and exit codes follow
# verify.sh review-state, plus pr_number=, pr_base=, pr_head= and same_repo=. With --save-dir,
# pr.json and timeline.json (comments and reviews, oldest first) are kept for the next step.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

usage_error() { echo "$*" >&2; exit 2; }

repo="" pr="" pr_file="" comments_file="" reviews_file="" save_dir="" ROOT=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage_error "missing value for $1"
  case "$1" in
    --repo) repo="$2" ;;
    --pr) pr="$2" ;;
    --pr-file) pr_file="$2" ;;
    --comments-file) comments_file="$2" ;;
    --reviews-file) reviews_file="$2" ;;
    --save-dir) save_dir="$2" ;;
    --root) ROOT="$2" ;;
    *) usage_error "unknown argument: $1" ;;
  esac
  shift 2
done
command -v jq >/dev/null 2>&1 || usage_error "pr-state.sh needs jq"
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(cd "$ROOT" && pwd)" || exit 2
profile="$ROOT/.ai-collab/project.yaml"
[ -f "$profile" ] || usage_error "$profile missing"

# Automation trusts authorship, so a shared identity would let one party speak for another.
# GitHub logins are case-insensitive, so they are compared in lower case.
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
human="$(lower "$(aick_identity "$profile" human)")" builder="$(lower "$(aick_identity "$profile" builder)")"
reviewer="$(lower "$(aick_identity "$profile" reviewer)")"
for pair in "human=$human" "builder=$builder" "reviewer=$reviewer"; do
  value="${pair#*=}"
  case "$value" in
    ""|REPLACE_*|*[!A-Za-z0-9_.[\]-]*) usage_error "project.yaml: identities.${pair%%=*} is not set to a GitHub login; automation stays off (REVIEW_PROTOCOL §9.5)" ;;
  esac
done
if [ "$human" = "$builder" ] || [ "$human" = "$reviewer" ] || [ "$builder" = "$reviewer" ]; then
  usage_error "project.yaml: identities must be three different GitHub logins; automation stays off (REVIEW_PROTOCOL §9.5)"
fi

if [ -n "$repo$pr" ]; then
  [ -n "$repo" ] && [ -n "$pr" ] || usage_error "--repo and --pr go together"
  printf '%s\n' "$pr" | grep -qE '^[0-9]+$' || usage_error "invalid --pr: $pr"
  [ -n "${GITHUB_TOKEN:-}" ] || usage_error "GITHUB_TOKEN is required to read $repo#$pr"
  api="${GITHUB_API_URL:-https://api.github.com}/repos/$repo"
  dir="${save_dir:-$(mktemp -d)}"
  mkdir -p "$dir"
  get() {
    curl -fsSL --connect-timeout 20 --max-time 60 -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$1"
  }
  # Read every page of a list endpoint into one JSON array.
  get_all() {
    local page=1
    : > "$dir/pages.json"
    while :; do
      get "$1?per_page=100&page=$page" > "$dir/page.json" || return 1
      [ "$(jq length "$dir/page.json")" -gt 0 ] || break
      cat "$dir/page.json" >> "$dir/pages.json"
      page=$((page + 1))
    done
    jq -s 'add // []' "$dir/pages.json"
    rm -f "$dir/page.json" "$dir/pages.json"
  }
  pr_file="$dir/pr.json" comments_file="$dir/comments.json" reviews_file="$dir/reviews.json"
  get "$api/pulls/$pr" > "$pr_file" || usage_error "cannot read $repo#$pr"
  get_all "$api/issues/$pr/comments" > "$comments_file" || usage_error "cannot read comments of $repo#$pr"
  get_all "$api/pulls/$pr/reviews" > "$reviews_file" || usage_error "cannot read reviews of $repo#$pr"
fi
[ -n "$pr_file" ] && [ -f "$pr_file" ] && [ -n "$comments_file" ] && [ -f "$comments_file" ] \
  || usage_error "need --repo/--pr, or --pr-file and --comments-file"
[ -z "$reviews_file" ] || [ -f "$reviews_file" ] || usage_error "--reviews-file not found: $reviews_file"

# One timeline of issue comments and pull request reviews, oldest first.
timeline="$(jq -s '
  (.[0] | map({login: .user.login, body: (.body // ""), at: .created_at}))
  + ((.[1] // []) | map(select(.submitted_at != null) | {login: .user.login, body: (.body // ""), at: .submitted_at}))
  | sort_by(.at)' "$comments_file" "${reviews_file:-/dev/null}")" || usage_error "cannot parse comments or reviews"
if [ -n "$save_dir" ]; then
  mkdir -p "$save_dir"
  [ "$pr_file" -ef "$save_dir/pr.json" ] || cp "$pr_file" "$save_dir/pr.json"
  printf '%s\n' "$timeline" > "$save_dir/timeline.json"
fi

# Each record is read from its owner's comments only. When a key appears more than once in one
# comment, the last line wins, matching how a reviewer's summary ends with the status block.
records="$(printf '%s\n' "$timeline" | jq -r --arg human "$human" --arg builder "$builder" \
    --arg reviewer "$reviewer" --slurpfile pr "$pr_file" '
  def lines: (. // "") | split("\n") | map(sub("\r$"; ""));
  def field($k): [lines[] | capture("^" + $k + ":[ \t]*(?<v>.*?)[ \t]*$") | .v] | last;
  def sha: select(. != null and test("^[0-9a-f]{40}$"));
  $pr[0] as $p
  | ( [ if ($p.user.login | ascii_downcase) == $builder then $p.body else empty end ]
      + [ .[] | select((.login | ascii_downcase) == $builder) | .body ]
      | map(select(field("AI-Review") == "READY") | field("Ready-SHA") | sha) | last // "" ) as $ready
  | [ .[] | select((.login | ascii_downcase) == $reviewer) | .body
      | select(field("Review-Status") | . == "VERIFIED" or . == "CHANGES_REQUESTED")
      | (field("Reviewed-SHA") | sha) as $s
      | (field("Open-Findings") // "none") as $o
      | ($o | if ascii_downcase == "none" then [] else [splits("[,[:space:]]+")] | map(select(. != "")) end
          | join(",")) as $ids
      | $s + (if $ids == "" then "" else ":" + $ids end) ] as $reviewed
  | [ .[] | select((.login | ascii_downcase) == $human) | select(.body | field("Human-Decision") == "ALLOW_EXTRA_ROUND") ]
      | length as $extra
  | "ready=\($ready)", "extra=\($extra)", "number=\($p.number)", "base=\($p.base.sha)",
    "head=\($p.head.sha)",
    "same_repo=\(if $p.head.repo.full_name != null and $p.head.repo.full_name == $p.base.repo.full_name then "true" else "false" end)",
    ($reviewed[] | "reviewed=\(.)")
')" || usage_error "cannot parse $pr_file"
value() { printf '%s\n' "$records" | sed -n "s/^$1=//p"; }
ready="$(value ready)" head="$(value head)"

context() {
  printf 'pr_number=%s\npr_base=%s\npr_head=%s\nsame_repo=%s\n' "$(value number)" "$(value base)" "$head" "$(value same_repo)"
}
no_action() {
  printf 'decision=NO_ACTION\nreason=%s\nready=%s\n' "$1" "$ready"
  context
  exit 10
}
[ -n "$ready" ] || no_action no_ready_sha
# A READY for an older commit does not cover what was pushed after it (LG-01).
[ "$ready" = "$head" ] || no_action ready_not_head

set -- --ready "$ready" --human-extra-rounds "$(value extra)"
while IFS= read -r rec; do
  [ -n "$rec" ] && set -- "$@" --reviewed "$rec"
done <<EOF_RECORDS
$(value reviewed)
EOF_RECORDS
"$HERE/verify.sh" review-state --root "$ROOT" "$@"
code=$?
[ "$code" -eq 2 ] || context
exit "$code"
