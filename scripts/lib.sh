#!/usr/bin/env bash
# Shared helpers for install.sh and verify.sh. Installed with the kit so a project can verify
# itself without the kit repository.

AICK_BEGIN='<!-- BEGIN ai-collab-kit:managed -->'
AICK_END='<!-- END ai-collab-kit:managed -->'
AICK_PR_MARKER='<!-- ai-collab-kit:managed pull_request_template -->'
# Kit-managed files, relative to the kit root and to <project>/.ai-collab/kit/.
AICK_MANAGED_FILES=(
  VERSION
  AI_COLLAB_GUIDE.md
  AI_COLLAB_QUICK_RULES.md
  REVIEW_PROTOCOL.md
  REVIEWER_BOOTSTRAP.md
  roles/BUILDER.md
  roles/REVIEWER.md
  scripts/lib.sh
  scripts/verify.sh
  scripts/pr-state.sh
  scripts/ai-review.sh
  scripts/notify-discord.sh
  scripts/orchestrate.sh
)
# Top-level keys every project.yaml must define.
AICK_PROFILE_KEYS=(project owner roles tracking stricter_rules commands lint_baseline
  environments release emergency_fix restore_drill review loop_guard)
AICK_PR_FIELDS=("Current HEAD:" "Code under review:" "Validated commit:" "Deployed commit:")

aick_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Print the managed block body for an adapter. $1 = adapter name (CLAUDE.md|AGENTS.md),
# $2 = project root. Claude Code resolves @imports itself; other agents usually do not, so
# AGENTS.md carries a verbatim copy of the quick rules and the project profile.
aick_render_block() {
  local adapter="$1" root="$2" kit="$2/.ai-collab/kit"
  printf 'ai-collab-kit %s\n\n' "$(cat "$kit/VERSION")"
  case "$adapter" in
    CLAUDE.md)
      printf '@.ai-collab/kit/AI_COLLAB_QUICK_RULES.md\n\n@.ai-collab/project.yaml\n'
      ;;
    AGENTS.md)
      cat "$kit/AI_COLLAB_QUICK_RULES.md"
      printf '\n## 本專案設定（`.ai-collab/project.yaml` 的逐字副本）\n\n```yaml\n'
      cat "$root/.ai-collab/project.yaml"
      printf '```\n'
      ;;
    *) return 2 ;;
  esac
}

# Print the text between the managed markers of file $1 (markers excluded).
aick_extract_block() {
  awk -v b="$AICK_BEGIN" -v e="$AICK_END" '
    $0 == e { inside = 0 }
    inside { print }
    $0 == b { inside = 1 }
  ' "$1"
}

aick_has_markers() {
  grep -qxF "$AICK_BEGIN" "$1" && grep -qxF "$AICK_END" "$1"
}

# Print "key=value" for each "  key: value" line inside top-level block $2 of YAML file $1.
# Comments are dropped. Only flat blocks of scalars are supported, which is all the profile uses.
aick_profile_block() {
  awk -v block="$2" '
    /^[^[:space:]#]/ { inside = ($0 ~ "^" block ":[[:space:]]*(#.*)?$"); next }
    inside {
      line = $0; sub(/#.*/, "", line)
      if (line ~ /^[[:space:]]+[a-z_]+:/) {
        key = line; sub(/^[[:space:]]+/, "", key); sub(/:.*/, "", key)
        val = line; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
        print key "=" val
      }
    }' "$1"
}

# Print identities.$2 from project.yaml $1 without surrounding quotes; empty when unset.
aick_identity() {
  aick_profile_block "$1" identities | sed -n "s/^$2=//p" | tail -n 1 | sed "s/^[\"']//; s/[\"']\$//"
}
