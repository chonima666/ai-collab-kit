#!/usr/bin/env bash
# Install or upgrade ai-collab-kit in a project.
#   scripts/install.sh <project-root>
# Kit-managed files are replaced on every run. Project-owned content is never overwritten:
# .ai-collab/project.yaml, text outside the managed markers in CLAUDE.md/AGENTS.md, and a pull
# request template that the kit did not create.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
. "$KIT/scripts/lib.sh"

[ $# -eq 1 ] || { echo "usage: $0 <project-root>" >&2; exit 2; }
ROOT="$(cd "$1" && pwd)"
DEST="$ROOT/.ai-collab/kit"
[ "$ROOT" != "$KIT" ] || { echo "refusing to install the kit into itself" >&2; exit 2; }

previous="none"
[ -f "$ROOT/.ai-collab/VERSION" ] && previous="$(cat "$ROOT/.ai-collab/VERSION")"
version="$(cat "$KIT/VERSION")"

mkdir -p "$DEST"
: > "$ROOT/.ai-collab/MANIFEST.tmp"
for f in "${AICK_MANAGED_FILES[@]}"; do
  mkdir -p "$DEST/$(dirname "$f")"
  cp "$KIT/$f" "$DEST/$f"
  printf '%s  %s\n' "$(aick_sha256 "$DEST/$f")" "$f" >> "$ROOT/.ai-collab/MANIFEST.tmp"
done
chmod +x "$DEST/scripts/verify.sh"
mv "$ROOT/.ai-collab/MANIFEST.tmp" "$ROOT/.ai-collab/MANIFEST"
printf '%s\n' "$version" > "$ROOT/.ai-collab/VERSION"

if [ ! -f "$ROOT/.ai-collab/project.yaml" ]; then
  cp "$KIT/templates/project.yaml" "$ROOT/.ai-collab/project.yaml"
  echo "created .ai-collab/project.yaml: fill in every REPLACE_ value"
fi

warnings=0
pr="$ROOT/.github/pull_request_template.md"
if [ ! -f "$pr" ] || grep -qF "$AICK_PR_MARKER" "$pr"; then
  mkdir -p "$ROOT/.github"
  cp "$KIT/templates/pull_request_template.md" "$pr"
else
  echo "WARNING: $pr exists and is not kit-managed; left unchanged. Add the fields in" \
    "templates/pull_request_template.md yourself, or delete it and re-run." >&2
  warnings=$((warnings + 1))
fi

for adapter in CLAUDE.md AGENTS.md; do
  target="$ROOT/$adapter"
  if [ ! -f "$target" ]; then
    cp "$KIT/adapters/$adapter" "$target"
  elif ! aick_has_markers "$target"; then
    printf '\n%s\n%s\n' "$AICK_BEGIN" "$AICK_END" >> "$target"
    echo "WARNING: $adapter had no managed block; appended one after the existing content." >&2
    warnings=$((warnings + 1))
  fi
  block="$(mktemp)"
  aick_render_block "$adapter" "$ROOT" > "$block"
  awk -v b="$AICK_BEGIN" -v e="$AICK_END" -v src="$block" '
    $0 == b { print; while ((getline line < src) > 0) print line; skip = 1; next }
    $0 == e { skip = 0 }
    !skip { print }
  ' "$target" > "$target.tmp"
  mv "$target.tmp" "$target"
  rm -f "$block"
done

echo "ai-collab-kit $previous -> $version installed in $ROOT ($warnings warning(s))"
echo "next: fill .ai-collab/project.yaml, re-run install.sh to sync AGENTS.md, then run" \
  ".ai-collab/kit/scripts/verify.sh"
