#!/usr/bin/env bash
# End-to-end tests for install.sh and verify.sh against throwaway git repositories.
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
passed=0 failed=0

ok() { passed=$((passed + 1)); echo "ok   - $1"; }
bad() { failed=$((failed + 1)); echo "FAIL - $1"; }
expect_success() { local name="$1"; shift; if "$@" >"$WORK/out" 2>&1; then ok "$name"; else bad "$name"; sed 's/^/       /' "$WORK/out"; fi; }
expect_failure() { local name="$1" pattern="$2"; shift 2
  if "$@" >"$WORK/out" 2>&1; then bad "$name (unexpectedly succeeded)"
  elif grep -qF -- "$pattern" "$WORK/out"; then ok "$name"
  else bad "$name (missing '$pattern')"; sed 's/^/       /' "$WORK/out"; fi; }

new_project() {
  local dir="$WORK/$1"
  mkdir -p "$dir" && git -C "$dir" init -q && git -C "$dir" config user.email t@example.com \
    && git -C "$dir" config user.name test && git -C "$dir" commit -q --allow-empty -m init
  echo "$dir"
}
fill_profile() { sed -i.bak 's/REPLACE_[A-Z_]*/filled/g' "$1/.ai-collab/project.yaml" && rm -f "$1/.ai-collab/project.yaml.bak"; }
verify() { "$1/.ai-collab/kit/scripts/verify.sh" --root "$1"; }

# 1. Fresh install: verify refuses until the project profile is filled in, then passes.
p="$(new_project fresh)"
expect_success "fresh install succeeds" "$KIT/scripts/install.sh" "$p"
expect_failure "unfilled profile is rejected" "REPLACE_ placeholders remain" verify "$p"
fill_profile "$p"
expect_failure "AGENTS.md is stale after the profile changes" "AGENTS.md managed block is stale" verify "$p"
expect_success "re-install syncs AGENTS.md" "$KIT/scripts/install.sh" "$p"
expect_success "verify passes on a complete install" verify "$p"
grep -qF '@.ai-collab/kit/AI_COLLAB_QUICK_RULES.md' "$p/CLAUDE.md" && ok "CLAUDE.md imports the quick rules" || bad "CLAUDE.md imports the quick rules"
grep -qF '## 2. 硬性授權邊界' "$p/AGENTS.md" && ok "AGENTS.md embeds the hard boundaries" || bad "AGENTS.md embeds the hard boundaries"

# 2. Upgrade keeps project-owned content.
echo "project note outside the block" >> "$p/CLAUDE.md"
echo "# owner edit" >> "$p/.ai-collab/project.yaml"
"$KIT/scripts/install.sh" "$p" >/dev/null 2>&1
grep -qF "project note outside the block" "$p/CLAUDE.md" && ok "re-install keeps text outside the managed block" || bad "re-install keeps text outside the managed block"
grep -qF "# owner edit" "$p/.ai-collab/project.yaml" && ok "re-install never overwrites project.yaml" || bad "re-install never overwrites project.yaml"
expect_success "verify passes after upgrade" verify "$p"

# 3. Tampering is detected.
cp -r "$p" "$WORK/tamper1"
echo "- extra rule" >> "$WORK/tamper1/.ai-collab/kit/AI_COLLAB_QUICK_RULES.md"
expect_failure "local edit of a kit file is detected" "kit file edited locally" verify "$WORK/tamper1"
cp -r "$p" "$WORK/tamper2"
sed -i.bak 's/^- production 部署$/- production 部署（可略過）/' "$WORK/tamper2/AGENTS.md" && rm -f "$WORK/tamper2/AGENTS.md.bak"
expect_failure "edited managed block in AGENTS.md is detected" "AGENTS.md managed block is stale or edited" verify "$WORK/tamper2"
cp -r "$p" "$WORK/tamper3"
sed -i.bak '/^owner:/d' "$WORK/tamper3/.ai-collab/project.yaml" && rm -f "$WORK/tamper3/.ai-collab/project.yaml.bak"
expect_failure "missing profile key is detected" "missing top-level key 'owner'" verify "$WORK/tamper3"

# 4. Existing project files are respected.
q="$(new_project existing)"
mkdir -p "$q/.github" && echo "custom template" > "$q/.github/pull_request_template.md"
printf '# Existing CLAUDE.md\nkeep me\n' > "$q/CLAUDE.md"
expect_success "install into a project with existing files" "$KIT/scripts/install.sh" "$q"
grep -qx "custom template" "$q/.github/pull_request_template.md" && ok "unmanaged PR template is left unchanged" || bad "unmanaged PR template is left unchanged"
grep -qx "keep me" "$q/CLAUDE.md" && grep -qF '@.ai-collab/project.yaml' "$q/CLAUDE.md" && ok "existing CLAUDE.md keeps its content and gains the block" || bad "existing CLAUDE.md keeps its content and gains the block"
fill_profile "$q" && "$KIT/scripts/install.sh" "$q" >/dev/null 2>&1
expect_failure "custom PR template without the SHA fields fails verify" "PR template lacks field 'Validated commit:'" verify "$q"

# 5. Change classification after a validated commit.
r="$(new_project classify)"
v="$(git -C "$r" rev-parse HEAD)"
mkdir -p "$r/docs" "$r/tests" "$r/src"
echo a > "$r/docs/guide.md"; echo b > "$r/tests/test_x.py"; echo c > "$r/src/app.py"; echo d > "$r/config.toml"
git -C "$r" add -A && git -C "$r" commit -qm change
out="$("$KIT/scripts/verify.sh" pr --validated "$v" --root "$r")"
echo "$out" | grep -qF "code=1 config=1 tests=1 docs=1" && ok "pr mode counts every category" || { bad "pr mode counts every category"; echo "$out"; }
echo "$out" | grep -qF "  - src/app.py" && ok "pr mode lists code files" || bad "pr mode lists code files"
w="$(git -C "$r" rev-parse HEAD)"
echo e > "$r/README.md" && git -C "$r" add -A && git -C "$r" commit -qm docs
out="$("$KIT/scripts/verify.sh" pr --validated "$w" --root "$r")"
echo "$out" | grep -qF "code=0 config=0 tests=0 docs=1" && ok "docs-only change is reported as docs only" || { bad "docs-only change is reported as docs only"; echo "$out"; }
x="$(git -C "$r" rev-parse HEAD)"
echo '{}' > "$r/docs/evidence.json" && git -C "$r" add -A && git -C "$r" commit -qm evidence
out="$("$KIT/scripts/verify.sh" pr --validated "$x" --root "$r")"
echo "$out" | grep -qF "code=0 config=0 tests=0 docs=1" && ok "data files under docs/ count as docs" || { bad "data files under docs/ count as docs"; echo "$out"; }
expect_failure "unknown validated commit is rejected" "unknown commit" "$KIT/scripts/verify.sh" pr --validated deadbeef --root "$r"

# 6. The kit refuses to install into itself.
expect_failure "install into the kit itself is refused" "refusing to install the kit into itself" "$KIT/scripts/install.sh" "$KIT"

echo "passed=$passed failed=$failed"
[ "$failed" -eq 0 ]
