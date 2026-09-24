#!/usr/bin/env bash
# Verify an installed ai-collab-kit, classify changes after a validated commit, or apply the
# Loop Guard to a review state.
#   .ai-collab/kit/scripts/verify.sh [--root <project-root>]
#   .ai-collab/kit/scripts/verify.sh pr --validated <sha> [--head <ref>] [--root <project-root>]
#   .ai-collab/kit/scripts/verify.sh review-state --ready <sha> [--reviewed <sha>[:<id>,...]]...
#       [--human-extra-rounds <n>] [--root <project-root>]
# review-state never contacts GitHub: the caller passes the state it has already read.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

usage_error() { echo "$*" >&2; exit 2; }

mode=check validated="" head="" ROOT="" ready="" reviewed="" extra=""
case "${1:-}" in
  pr) mode=pr; shift ;;
  review-state) mode=review; shift ;;
esac
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage_error "missing value for $1"
  case "$1" in
    --validated) validated="$2" ;;
    --head) head="$2" ;;
    --root) ROOT="$2" ;;
    --ready) [ -z "$ready" ] || usage_error "--ready given more than once"; ready="$2" ;;
    --reviewed) reviewed="$reviewed$2
" ;;
    --human-extra-rounds) [ -z "$extra" ] || usage_error "--human-extra-rounds given more than once"; extra="$2" ;;
    *) usage_error "unknown argument: $1" ;;
  esac
  shift 2
done
if [ "$mode" = review ]; then
  [ -z "$validated$head" ] || usage_error "--validated and --head are not review-state options"
else
  [ -z "$ready$reviewed$extra" ] || usage_error "--ready, --reviewed and --human-extra-rounds need review-state mode"
fi
[ -n "$head" ] || head=HEAD
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(cd "$ROOT" && pwd)" || exit 2

# Print "max_review_rounds=<n>" and "require_new_sha_for_rereview=<v>" from the loop_guard block
# of project.yaml $1, or print a reason and return 1. The limit comes only from this file, which
# the project changes through a reviewed PR; no command-line option can raise it (LG-06a).
loop_guard_config() {
  local entries max new_sha
  grep -qE '^loop_guard:[[:space:]]*(#.*)?$' "$1" || { echo "project.yaml: missing top-level key 'loop_guard'"; return 1; }
  entries="$(aick_profile_block "$1" loop_guard)"
  max="$(printf '%s\n' "$entries" | grep '^max_review_rounds=' || true)"
  new_sha="$(printf '%s\n' "$entries" | grep '^require_new_sha_for_rereview=' || true)"
  { [ "$(printf '%s\n' "$max" | grep -c .)" -eq 1 ] && printf '%s\n' "$max" | grep -qxE 'max_review_rounds=[1-9][0-9]{0,2}'; } \
    || { echo "project.yaml: loop_guard.max_review_rounds must be set once, as an integer from 1 to 999"; return 1; }
  # v0.1.1 supports only true; re-reviewing an already reviewed SHA is not a mode it offers.
  [ "$new_sha" = "require_new_sha_for_rereview=true" ] \
    || { echo "project.yaml: loop_guard.require_new_sha_for_rereview must be set once, to true"; return 1; }
  printf '%s\n%s\n' "$max" "$new_sha"
}

if [ "$mode" = review ]; then
  sha_re='^[0-9a-f]{40}$'
  [ -n "$ready" ] || usage_error "review-state requires --ready <40-character sha>"
  printf '%s\n' "$ready" | grep -qE "$sha_re" || usage_error "invalid --ready sha: $ready"
  [ -n "$extra" ] || extra=0
  printf '%s\n' "$extra" | grep -qE '^[0-9]{1,3}$' || usage_error "invalid --human-extra-rounds: $extra"
  extra=$((10#$extra))
  # Each --reviewed record is one Reviewed-SHA that carries a Review-Status, in the order posted,
  # with the finding IDs the reviewer still left open at that SHA.
  records=""
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    sha="${rec%%:*}" ids=""
    [ "$sha" = "$rec" ] || ids="${rec#*:}"
    printf '%s\n' "$sha" | grep -qE "$sha_re" || usage_error "invalid --reviewed sha: $rec"
    if [ -n "$ids" ]; then
      printf '%s\n' "$ids" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*(,[A-Za-z0-9][A-Za-z0-9._-]*)*$' \
        || usage_error "invalid finding IDs in --reviewed: $rec"
    fi
    records="$records$sha	$ids
"
  done <<EOF_REVIEWED
$reviewed
EOF_REVIEWED
  profile="$ROOT/.ai-collab/project.yaml"
  [ -f "$profile" ] || usage_error "$profile missing; the Loop Guard limit is read only from project.yaml"
  config="$(loop_guard_config "$profile")" || usage_error "$config"
  max="$(printf '%s\n' "$config" | sed -n 's/^max_review_rounds=//p')"

  # A round is a distinct Reviewed-SHA: repeating a SHA never adds a round, and its latest record
  # holds its open findings. A finding open at two distinct SHAs is a repeated unresolved dispute;
  # the round in which that first happens caps the rounds like max_review_rounds does.
  state="$(printf '%s' "$records" | awk -F'\t' -v ready="$ready" '
    !($1 in ord) { ord[$1] = ++n; sha[n] = $1 }
    { open[$1] = $2 }
    END {
      seen = 0; first = 0; disputed = ""
      for (i = 1; i <= n; i++) {
        if (sha[i] == ready) seen = 1
        k = split(open[sha[i]], ids, ",")
        for (j = 1; j <= k; j++) {
          if ((i, ids[j]) in listed) continue
          listed[i, ids[j]] = 1
          if (++count[ids[j]] == 2) {
            if (!first) first = i
            disputed = disputed (disputed == "" ? "" : ",") ids[j]
          }
        }
      }
      print "rounds=" n + 0
      print "last=" (n ? sha[n] : "none")
      print "carry=" (n ? open[sha[n]] : "")
      print "seen=" seen
      print "dispute_round=" first
      print "disputed=" disputed
    }')"
  get() { printf '%s\n' "$state" | sed -n "s/^$1=//p"; }
  rounds="$(get rounds)" last="$(get last)" carry="$(get carry)"
  dispute_round="$(get dispute_round)" disputed="$(get disputed)"
  base="$max"
  [ "$dispute_round" -gt 0 ] && [ "$dispute_round" -lt "$base" ] && base="$dispute_round"
  limit=$((base + extra))

  if [ "$(get seen)" = 1 ]; then
    decision=NO_ACTION reason=already_reviewed code=10
  elif [ "$rounds" -ge "$limit" ]; then
    # reason is a single value. When both limits bind, the dispute wins: it names the findings the
    # Human has to decide on, and rounds/limit still show that the round limit is reached.
    decision=HUMAN_GATE_REQUIRED code=20 reason=max_review_rounds
    if [ "$dispute_round" -gt 0 ] && [ "$rounds" -ge $((dispute_round + extra)) ]; then
      reason=repeated_unresolved_finding
    fi
  else
    decision=REVIEW reason=new_ready_sha code=0
  fi
  echo "decision=$decision"
  echo "reason=$reason"
  echo "rounds=$rounds"
  echo "limit=$limit"
  echo "ready=$ready"
  echo "last_reviewed=$last"
  if [ "$decision" = REVIEW ]; then
    echo "review_round=$((rounds + 1))"
    if [ "$last" = none ]; then echo "scope=full"; else echo "scope=$last..$ready"; fi
    echo "carry_findings=$carry"
  fi
  [ "$decision" = HUMAN_GATE_REQUIRED ] && [ -n "$disputed" ] && echo "disputed_findings=$disputed"
  exit "$code"
fi

# Path classification is deliberately conservative: anything not recognised as docs, tests or
# config counts as code, so a mislabelled change is reported as code rather than hidden.
classify() {
  case "$1" in
    tests/*|test/*|*/tests/*|*/test/*|spec/*|*_test.*|*/test_*|test_*|*.test.*|*.spec.*) echo tests ;;
    docs/*|*/docs/*) echo docs ;;
    .github/workflows/*|Dockerfile*|*/Dockerfile*|*.yaml|*.yml|*.toml|*.json|*.ini|*.cfg|*.lock|.env*) echo config ;;
    *.md|*.rst|*.txt|LICENSE*|.ai/*|.ai-collab/*) echo docs ;;
    *) echo code ;;
  esac
}

if [ "$mode" = pr ]; then
  [ -n "$validated" ] || { echo "pr mode requires --validated <sha>" >&2; exit 2; }
  cd "$ROOT" || exit 2
  v="$(git rev-parse --verify "$validated^{commit}" 2>/dev/null)" || { echo "unknown commit: $validated" >&2; exit 2; }
  h="$(git rev-parse --verify "$head^{commit}" 2>/dev/null)" || { echo "unknown ref: $head" >&2; exit 2; }
  if ! git merge-base --is-ancestor "$v" "$h"; then
    echo "ERROR: validated commit $v is not an ancestor of $head; the change list would be meaningless" >&2
    exit 2
  fi
  listing="$(git diff --name-only "$v" "$h" | while IFS= read -r path; do
    [ -n "$path" ] && printf '%s\t%s\n' "$(classify "$path")" "$path"
  done)"
  count() { printf '%s\n' "$listing" | grep -c "^$1	" || true; }
  echo "Validated commit: $v"
  echo "Current HEAD: $h"
  echo "Changes after validated commit: code=$(count code) config=$(count config) tests=$(count tests) docs=$(count docs)"
  for c in code config tests docs; do
    if [ "$(count "$c")" -gt 0 ]; then
      echo "$c:"
      printf '%s\n' "$listing" | grep "^$c	" | cut -f2- | sed 's/^/  - /'
    fi
  done
  exit 0
fi

fail=0
problem() { echo "FAIL: $*"; fail=1; }

kit="$ROOT/.ai-collab/kit"
[ -f "$ROOT/.ai-collab/VERSION" ] || problem ".ai-collab/VERSION missing (run install.sh)"
[ -f "$ROOT/.ai-collab/MANIFEST" ] || problem ".ai-collab/MANIFEST missing (run install.sh)"
if [ -f "$ROOT/.ai-collab/MANIFEST" ]; then
  while read -r sum path; do
    if [ ! -f "$kit/$path" ]; then
      problem "kit file missing: .ai-collab/kit/$path"
    elif [ "$(aick_sha256 "$kit/$path")" != "$sum" ]; then
      problem "kit file edited locally: .ai-collab/kit/$path (change it upstream in ai-collab-kit)"
    fi
  done < "$ROOT/.ai-collab/MANIFEST"
fi
if [ -f "$ROOT/.ai-collab/VERSION" ] && [ -f "$kit/VERSION" ] \
    && [ "$(cat "$ROOT/.ai-collab/VERSION")" != "$(cat "$kit/VERSION")" ]; then
  problem ".ai-collab/VERSION does not match .ai-collab/kit/VERSION"
fi

profile="$ROOT/.ai-collab/project.yaml"
if [ ! -f "$profile" ]; then
  problem ".ai-collab/project.yaml missing"
else
  for key in "${AICK_PROFILE_KEYS[@]}"; do
    grep -qE "^$key:" "$profile" || problem "project.yaml: missing top-level key '$key'"
  done
  if grep -qE '^loop_guard:' "$profile" && ! lg="$(loop_guard_config "$profile")"; then
    problem "$lg"
  fi
  # Ignore comments so documentation about placeholders is not itself a placeholder.
  if sed 's/#.*//' "$profile" | grep -qE 'REPLACE_[A-Z][A-Z_]*'; then
    problem "project.yaml: REPLACE_ placeholders remain"
  fi
fi

for adapter in CLAUDE.md AGENTS.md; do
  target="$ROOT/$adapter"
  if [ ! -f "$target" ]; then
    problem "$adapter missing"
  elif ! aick_has_markers "$target"; then
    problem "$adapter has no managed block"
  elif [ -f "$profile" ] && [ -f "$kit/VERSION" ] && [ -f "$kit/AI_COLLAB_QUICK_RULES.md" ]; then
    if ! diff -q <(aick_render_block "$adapter" "$ROOT") <(aick_extract_block "$target") >/dev/null; then
      problem "$adapter managed block is stale or edited (re-run install.sh)"
    fi
  fi
done

pr="$ROOT/.github/pull_request_template.md"
if [ ! -f "$pr" ]; then
  problem ".github/pull_request_template.md missing"
else
  for field in "${AICK_PR_FIELDS[@]}"; do
    grep -qF -- "$field" "$pr" || problem "PR template lacks field '$field'"
  done
fi

if [ "$fail" -eq 0 ]; then
  echo "ai-collab-kit $(cat "$ROOT/.ai-collab/VERSION"): OK"
fi
exit "$fail"
