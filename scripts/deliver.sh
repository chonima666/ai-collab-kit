#!/usr/bin/env bash
# Automatic delivery for one pull request (REVIEW_PROTOCOL §10).
#   deliver.sh --repo <owner/repo> --pr <n> [--trigger review|ci] [--root <project-root>]
#       [--work-dir <dir>]
# Rebuilds the state from GitHub, runs the Policy Gate, posts the result as the commit status
# "ai-collab/gate" on the head commit, and merges only on AUTO_MERGE_ALLOWED. The merge is pinned to
# the head that was judged, so a push after the decision makes GitHub refuse it. Nothing is
# carried over from an earlier run: a re-run decides again from GitHub.
# Environment:
#   GITHUB_TOKEN          read access to the repository, its checks and the pull request
#   AICK_MERGER_TOKEN     Merger GitHub App installation token: posts the status and merges
#   AICK_DISCORD_WEBHOOK  optional Discord webhook for notifications
# Exit codes: 0 done (merged, waiting, or stopped at the Human Gate), 2 configuration or input
# error, 5 fork pull request refused, 6 posting the status or merging failed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage_error() { echo "$*" >&2; exit 2; }

repo="" pr="" trigger=ci ROOT="" work=""
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
case "$trigger" in review|ci) ;; *) usage_error "--trigger must be review or ci" ;; esac
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(cd "$ROOT" && pwd)" || exit 2
[ -n "$work" ] || work="$(mktemp -d)"
mkdir -p "$work"
api="${GITHUB_API_URL:-https://api.github.com}/repos/$repo"

"$HERE/pr-state.sh" --repo "$repo" --pr "$pr" --root "$ROOT" --save-dir "$work" > "$work/state"
code=$?
cat "$work/state"
[ "$code" -ne 2 ] || exit 2
state() { sed -n "s/^$1=//p" "$work/state" | tail -n 1; }
head="$(state pr_head)" base="$(state pr_base)"
notify() { "$HERE/notify-discord.sh" "$1" "$repo" "$pr" "$head" "${2:-}"; }

if [ "$(state same_repo)" != true ]; then
  echo "refused: $repo#$pr comes from a fork; automatic delivery runs only for same-repository pull requests" >&2
  exit 5
fi
[ "$(state pr_state)" = open ] || { echo "$repo#$pr is $(state pr_state); nothing to deliver"; exit 0; }

# The changed files come from git objects; the pull request's code is never checked out or run.
for sha in "$base" "$head"; do
  git -C "$ROOT" cat-file -e "$sha^{commit}" 2>/dev/null && continue
  git -C "$ROOT" fetch --no-tags --quiet origin "+refs/pull/$pr/head:refs/remotes/aick/pr-$pr" \
    "+refs/heads/$(state pr_base_ref):refs/remotes/aick/base-$pr" || usage_error "cannot fetch the commits of $repo#$pr"
  break
done
git -C "$ROOT" diff --no-renames --name-only -z "$base...$head" > "$work/paths" \
  || usage_error "cannot list the files changed by $repo#$pr"
curl -fsSL --connect-timeout 20 --max-time 60 -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
  "$api/commits/$head/check-runs?per_page=100" > "$work/checks.json" \
  || usage_error "cannot read the checks of $head"

"$HERE/policy-gate.sh" --state "$work/state" --paths "$work/paths" --checks "$work/checks.json" \
  --root "$ROOT" > "$work/gate"
gate=$?
cat "$work/gate"
[ "$gate" -ne 2 ] || exit 2
decision="$(sed -n 's/^decision=//p' "$work/gate")" reason="$(sed -n 's/^reason=//p' "$work/gate")"
summary="$reason$(sed -nE 's/^(protected_paths|risk_flags|failed_checks|pending_checks|loop_guard_reason)=/ \1=/p' "$work/gate" | tr -d '\n')"

fail() {
  echo "AUTO_MERGE_FAILED: $1" >&2
  [ "$decision" != AUTO_MERGE_ALLOWED ] || notify AUTO_MERGE_FAILED "$1" || true
  exit "$2"
}
# There is no fallback identity: without the Merger App nothing is posted and nothing is merged.
[ -n "${AICK_MERGER_TOKEN:-}" ] || fail "the Merger App token is not available" 2
(umask 077; printf 'Authorization: Bearer %s\n' "$AICK_MERGER_TOKEN" > "$work/auth")
merger() {
  curl -sS -o "$work/response.json" -w '%{http_code}' --connect-timeout 20 --max-time 60 \
    -H @"$work/auth" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}

# The status is what the ruleset on the default branch requires, so it also stops a manual merge.
case "$gate" in 0) status=success ;; 10) status=pending ;; *) status=failure ;; esac
jq -n --arg s "$status" --arg d "$(printf '%s: %s' "$decision" "$summary" | cut -c1-140)" \
  '{state: $s, context: "ai-collab/gate", description: $d}' > "$work/status.json"
http="$(merger --data-binary @"$work/status.json" "$api/statuses/$head")" || http=000
[ "$http" = 201 ] || { rm -f "$work/auth"; fail "posting the ai-collab/gate status failed (HTTP $http)" 6; }

case "$gate" in
  10) rm -f "$work/auth"; echo "NOT_READY: $summary; no merge"; exit 0 ;;
  20)
    rm -f "$work/auth"
    echo "HUMAN_GATE_REQUIRED: $summary; no merge"
    # The gate is decided at review time, so only the run that follows the review announces it.
    [ "$trigger" = review ] || exit 0
    notify HUMAN_GATE_REQUIRED "$summary" || true
    exit 0 ;;
esac

jq -n --arg sha "$head" '{sha: $sha, merge_method: "merge"}' > "$work/merge.json"
http="$(merger -X PUT --data-binary @"$work/merge.json" "$api/pulls/$pr/merge")" || http=000
rm -f "$work/auth"
[ "$http" = 200 ] && [ "$(jq -r '.merged // false' "$work/response.json")" = true ] \
  || fail "GitHub refused the merge of $head (HTTP $http): $(jq -r '.message // empty' "$work/response.json" 2>/dev/null | head -c 200)" 6
echo "merged: $repo#$pr at $head"
notify AUTO_MERGED "merged at $head" || true
exit 0
