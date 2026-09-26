#!/usr/bin/env bash
# Run one automated review step for a pull request (REVIEW_PROTOCOL §9.6).
#   orchestrate.sh --repo <owner/repo> --pr <n> [--trigger ready|other] [--root <project-root>]
#       [--work-dir <dir>]
# Order: rebuild the state from GitHub, apply the Loop Guard, and only on decision=REVIEW call
# the model and post the result as the Reviewer App. NO_ACTION does nothing;
# HUMAN_GATE_REQUIRED only notifies Discord, and only when a READY request triggered the run.
# Environment:
#   GITHUB_TOKEN           read access to the repository and its checks (never used to write)
#   AICK_REVIEWER_TOKEN    Reviewer GitHub App installation token, used only to post the review
#   OPENAI_API_KEY         model API key
#   AICK_REVIEWER_MODEL    model name
#   AICK_DISCORD_WEBHOOK   optional Discord webhook for notifications
# Exit codes: 0 done (including NO_ACTION and a notified gate), 1 notification of a gate failed,
# 2 configuration or input error, 3 model output rejected, 4 model API failure, 5 fork pull
# request refused, 6 posting as the Reviewer App failed. Every failure after the Loop Guard
# said REVIEW is also sent to Discord as REVIEW_FAILED.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

usage_error() { echo "$*" >&2; exit 2; }

repo="" pr="" trigger=other ROOT="" work=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage_error "missing value for $1"
  case "$1" in
    --repo) repo="$2" ;;
    --pr) pr="$2" ;;
    --trigger) trigger="$2" ;;
    --root) ROOT="$2" ;;
    --work-dir) work="$2" ;;
    *) usage_error "unknown argument: $1" ;;
  esac
  shift 2
done
[ -n "$repo" ] && [ -n "$pr" ] || usage_error "--repo and --pr are required"
case "$trigger" in ready|other) ;; *) usage_error "--trigger must be ready or other" ;; esac
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(cd "$ROOT" && pwd)" || exit 2
[ -n "$work" ] || work="$(mktemp -d)"
mkdir -p "$work"

"$HERE/pr-state.sh" --repo "$repo" --pr "$pr" --root "$ROOT" --save-dir "$work" > "$work/state"
code=$?
cat "$work/state"
[ "$code" -ne 2 ] || exit 2
state() { sed -n "s/^$1=//p" "$work/state" | tail -n 1; }
ready="$(state ready)"
notify() { "$HERE/notify-discord.sh" "$1" "$repo" "$pr" "$ready" "${2:-}"; }

# Secrets are only ever used for pull requests whose code lives in this repository.
if [ "$(state same_repo)" != true ]; then
  echo "refused: $repo#$pr comes from a fork; automated review runs only for same-repository pull requests" >&2
  exit 5
fi

case "$code" in
  10)
    echo "NO_ACTION: no model call"
    exit 0 ;;
  20)
    echo "HUMAN_GATE_REQUIRED: no model call"
    # A gate stays in place until a Human acts, so only the READY request that hit it is announced.
    [ "$trigger" = ready ] || exit 0
    notify HUMAN_GATE_REQUIRED "reason=$(state reason) rounds=$(state rounds) limit=$(state limit)$(
      d="$(state disputed_findings)"; [ -z "$d" ] || printf ' disputed=%s' "$d")" || exit 1
    exit 0 ;;
  0) ;;
  *) echo "unexpected review-state exit code $code" >&2; exit 2 ;;
esac

# decision=REVIEW. Every requirement is checked before any money is spent, and each failure stops
# the run: there is no fallback to another identity or token.
fail() {
  echo "REVIEW_FAILED: $2" >&2
  notify REVIEW_FAILED "$2" || true
  exit "$1"
}
[ -n "${AICK_REVIEWER_MODEL:-}" ] || fail 2 "AICK_REVIEWER_MODEL is not set"
[ -n "${OPENAI_API_KEY:-}" ] || fail 2 "OPENAI_API_KEY is not set"
[ -n "${AICK_REVIEWER_TOKEN:-}" ] || fail 2 "the Reviewer App token is not available"
reviewer="$(aick_identity "$ROOT/.ai-collab/project.yaml" reviewer | tr '[:upper:]' '[:lower:]')"

# The pull request's commits are fetched as data for the diff; they are never checked out or run.
if ! git -C "$ROOT" cat-file -e "$ready^{commit}" 2>/dev/null; then
  git -C "$ROOT" fetch --no-tags --quiet origin "+refs/pull/$pr/head:refs/remotes/aick/pr-$pr" \
    || fail 2 "cannot fetch the commits of $repo#$pr"
fi

# The check runs on the Ready-SHA, read from GitHub here and handed to the Reviewer as trusted data.
# A failed read leaves no file, and the Reviewer is then told that the CI data is unavailable.
curl -fsSL --connect-timeout 20 --max-time 60 -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
  "${GITHUB_API_URL:-https://api.github.com}/repos/$repo/commits/$ready/check-runs?per_page=100" \
  > "$work/checks.json" 2>/dev/null || rm -f "$work/checks.json"

notify REVIEW_STARTED "round $(state review_round) of $(state limit), scope $(state scope)" || true
"$HERE/ai-review.sh" --state "$work/state" --pr-file "$work/pr.json" --timeline-file "$work/timeline.json" \
  --repo "$repo" --checks-file "$work/checks.json" \
  --model "$AICK_REVIEWER_MODEL" --raw-out "$work/model-output.txt" --root "$ROOT" > "$work/review.md"
code=$?
case "$code" in
  0) ;;
  3) fail 3 "the model output broke the review contract; nothing was posted" ;;
  4) fail 4 "the model API failed or timed out; nothing was posted" ;;
  *) fail 2 "the reviewer runtime failed (exit $code); nothing was posted" ;;
esac

# Posted as a pull request review of exactly the Ready-SHA, with event COMMENT: the Reviewer App
# never approves or requests changes through GitHub's own review states.
jq -n --arg body "$(cat "$work/review.md")" --arg sha "$ready" '{commit_id: $sha, body: $body, event: "COMMENT"}' \
  > "$work/post.json"
(umask 077; printf 'Authorization: Bearer %s\n' "$AICK_REVIEWER_TOKEN" > "$work/auth")
http="$(curl -sS -o "$work/posted.json" -w '%{http_code}' --connect-timeout 20 --max-time 60 \
  -H @"$work/auth" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
  --data-binary @"$work/post.json" "${GITHUB_API_URL:-https://api.github.com}/repos/$repo/pulls/$pr/reviews")" \
  || http=000
rm -f "$work/auth"
[ "$http" = 200 ] || fail 6 "posting the review as the Reviewer App failed (HTTP $http)"
author="$(jq -r '.user.login // empty' "$work/posted.json" | tr '[:upper:]' '[:lower:]')"
[ "$author" = "$reviewer" ] \
  || fail 6 "the review was posted as '$author', not identities.reviewer '$reviewer'; it does not count"

status="$(sed -n 's/^Review-Status: //p' "$work/review.md" | tail -n 1)"
open="$(sed -n 's/^Open-Findings: //p' "$work/review.md" | tail -n 1)"
echo "posted: $status, Open-Findings: $open"
case "$status" in
  VERIFIED) notify REVIEW_VERIFIED "round $(state review_round)" || true ;;
  *) notify CHANGES_REQUESTED "round $(state review_round), open: $open" || true ;;
esac
exit 0
