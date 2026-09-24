#!/usr/bin/env bash
# Verify an installed ai-collab-kit, or classify changes after a validated commit.
#   .ai-collab/kit/scripts/verify.sh [--root <project-root>]
#   .ai-collab/kit/scripts/verify.sh pr --validated <sha> [--head <ref>] [--root <project-root>]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

mode=check validated="" head=HEAD ROOT=""
[ "${1:-}" = pr ] && { mode=pr; shift; }
while [ $# -gt 0 ]; do
  case "$1" in
    --validated) validated="$2"; shift 2 ;;
    --head) head="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(cd "$ROOT" && pwd)"

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
