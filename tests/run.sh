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
# Replace only placeholder values, the way a person would; comments stay untouched.
fill_profile() { sed -i.bak 's/REPLACE_[A-Z][A-Z_]*/filled/g' "$1/.ai-collab/project.yaml" && rm -f "$1/.ai-collab/project.yaml.bak"; }
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
[ -f "$p/.ai-collab/kit/REVIEWER_BOOTSTRAP.md" ] && ok "reviewer bootstrap is installed" || bad "reviewer bootstrap is installed"
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
cp -r "$p" "$WORK/comment"
echo "# note: keep REPLACE_EXAMPLE out of values" >> "$WORK/comment/.ai-collab/project.yaml"
"$KIT/scripts/install.sh" "$WORK/comment" >/dev/null 2>&1
expect_success "placeholder-looking text in a comment is ignored" verify "$WORK/comment"

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
base="$(git -C "$r" rev-parse HEAD)"
git -C "$r" checkout -q -b side && echo s > "$r/side.py" && git -C "$r" add -A && git -C "$r" commit -qm side
side="$(git -C "$r" rev-parse HEAD)"
git -C "$r" checkout -q - && echo m > "$r/main.py" && git -C "$r" add -A && git -C "$r" commit -qm mainline
expect_failure "validated commit outside HEAD's history is an error" "is not an ancestor" "$KIT/scripts/verify.sh" pr --validated "$side" --root "$r"
expect_success "validated ancestor still classifies" "$KIT/scripts/verify.sh" pr --validated "$base" --root "$r"
expect_failure "unknown validated commit is rejected" "unknown commit" "$KIT/scripts/verify.sh" pr --validated deadbeef --root "$r"

# 6. The kit refuses to install into itself.
expect_failure "install into the kit itself is refused" "refusing to install the kit into itself" "$KIT/scripts/install.sh" "$KIT"

# 7. Loop Guard (REVIEW_PROTOCOL §9): review-state decides from the state it is given.
# expect_state <name> <exit code> <line;line...> -- <review-state arguments>
expect_state() { local name="$1" want_code="$2" want="$3" code w missing=""; shift 4
  "$KIT/scripts/verify.sh" review-state --root "$p" "$@" >"$WORK/out" 2>&1; code=$?
  local IFS=';'
  for w in $want; do grep -qxF -- "$w" "$WORK/out" || missing="$missing [$w]"; done
  if [ "$code" = "$want_code" ] && [ -z "$missing" ]; then ok "$name"
  else bad "$name (exit $code, want $want_code;${missing:+ missing$missing})"; sed 's/^/       /' "$WORK/out"; fi; }
s1="$(printf '%040d' 1)" s2="$(printf '%040d' 2)" s3="$(printf '%040d' 3)" s4="$(printf '%040d' 4)" s5="$(printf '%040d' 5)"
expect_state "round 1: a new Ready-SHA is reviewed in full" 0 "decision=REVIEW;review_round=1;scope=full" -- --ready "$s1"
expect_state "Ready-SHA equal to the last Reviewed-SHA is NO_ACTION" 10 "decision=NO_ACTION;reason=already_reviewed" -- \
  --ready "$s2" --reviewed "$s1" --reviewed "$s2"
expect_state "an earlier Reviewed-SHA offered again is NO_ACTION" 10 "decision=NO_ACTION" -- \
  --ready "$s1" --reviewed "$s1" --reviewed "$s2"
expect_state "round 3 with a new Ready-SHA is still reviewed" 0 "decision=REVIEW;review_round=3;scope=$s2..$s3" -- \
  --ready "$s3" --reviewed "$s1" --reviewed "$s2"
expect_state "a new Ready-SHA after round 3 needs the Human" 20 "decision=HUMAN_GATE_REQUIRED;reason=max_review_rounds;rounds=3" -- \
  --ready "$s4" --reviewed "$s1" --reviewed "$s2" --reviewed "$s3"
expect_state "a repeated Reviewed-SHA does not add a round" 0 "decision=REVIEW;rounds=2;review_round=3" -- \
  --ready "$s3" --reviewed "$s1" --reviewed "$s1" --reviewed "$s2" --reviewed "$s2"
expect_state "a finding open at two Ready-SHAs needs the Human" 20 \
  "decision=HUMAN_GATE_REQUIRED;reason=repeated_unresolved_finding;disputed_findings=R1-02" -- \
  --ready "$s3" --reviewed "$s1:R1-01,R1-02" --reviewed "$s2:R1-02"
expect_state "different open findings per SHA are not a dispute" 0 "decision=REVIEW;carry_findings=R2-01" -- \
  --ready "$s3" --reviewed "$s1:R1-01" --reviewed "$s2:R2-01"
expect_state "a finding listed twice at one SHA is not a dispute" 0 "decision=REVIEW" -- \
  --ready "$s2" --reviewed "$s1:R1-01,R1-01"
expect_state "ALLOW_EXTRA_ROUND permits one more round" 0 "decision=REVIEW;review_round=4;limit=4" -- \
  --ready "$s4" --reviewed "$s1" --reviewed "$s2" --reviewed "$s3" --human-extra-rounds 1
expect_state "ALLOW_EXTRA_ROUND permits only one more round" 20 "decision=HUMAN_GATE_REQUIRED;reason=max_review_rounds" -- \
  --ready "$s5" --reviewed "$s1" --reviewed "$s2" --reviewed "$s3" --reviewed "$s4" --human-extra-rounds 1
expect_state "ALLOW_EXTRA_ROUND after a dispute permits one more round" 0 "decision=REVIEW;review_round=3" -- \
  --ready "$s3" --reviewed "$s1:R1-02" --reviewed "$s2:R1-02" --human-extra-rounds 1
expect_state "the gate returns after the extra round" 20 "decision=HUMAN_GATE_REQUIRED;reason=repeated_unresolved_finding" -- \
  --ready "$s4" --reviewed "$s1:R1-02" --reviewed "$s2:R1-02" --reviewed "$s3" --human-extra-rounds 1
expect_state "when both limits bind, reason is the single value repeated_unresolved_finding" 20 \
  "decision=HUMAN_GATE_REQUIRED;reason=repeated_unresolved_finding;disputed_findings=R1-02;rounds=4" -- \
  --ready "$s5" --reviewed "$s1:R1-02" --reviewed "$s2:R1-02" --reviewed "$s3" --reviewed "$s4" --human-extra-rounds 1
expect_state "missing --ready is invalid input" 2 "review-state requires --ready <40-character sha>" --
expect_state "short Ready-SHA is invalid input" 2 "invalid --ready sha: abc123" -- --ready abc123
expect_state "malformed Reviewed-SHA is invalid input" 2 "invalid --reviewed sha: XYZ" -- --ready "$s1" --reviewed XYZ
expect_state "malformed finding IDs are invalid input" 2 "invalid finding IDs in --reviewed: $s1:R1,,R2" -- \
  --ready "$s2" --reviewed "$s1:R1,,R2"
expect_state "option without a value is invalid input" 2 "missing value for --ready" -- --ready
expect_state "negative extra rounds are invalid input" 2 "invalid --human-extra-rounds: -1" -- --ready "$s1" --human-extra-rounds -1
expect_state "the round limit cannot be passed on the command line" 2 "unknown argument: --max-rounds" -- \
  --ready "$s4" --reviewed "$s1" --reviewed "$s2" --reviewed "$s3" --max-rounds 9
expect_failure "review-state options are rejected outside review-state" "need review-state mode" "$KIT/scripts/verify.sh" --root "$p" --ready "$s1"
cp -r "$p" "$WORK/lg1"
sed -i.bak 's/max_review_rounds: 3/max_review_rounds: many/' "$WORK/lg1/.ai-collab/project.yaml" && rm -f "$WORK/lg1/.ai-collab/project.yaml.bak"
expect_failure "invalid max_review_rounds fails verify" "loop_guard.max_review_rounds must be set once" verify "$WORK/lg1"
expect_failure "review-state refuses an invalid limit" "loop_guard.max_review_rounds must be set once" \
  "$KIT/scripts/verify.sh" review-state --root "$WORK/lg1" --ready "$s1"
cp -r "$p" "$WORK/lg4"
sed -i.bak 's/^  max_review_rounds: 3.*/&\
  max_review_rounds: 9/' "$WORK/lg4/.ai-collab/project.yaml" && rm -f "$WORK/lg4/.ai-collab/project.yaml.bak"
expect_failure "a second max_review_rounds cannot raise the limit" "loop_guard.max_review_rounds must be set once" \
  "$KIT/scripts/verify.sh" review-state --root "$WORK/lg4" --ready "$s1"
cp -r "$p" "$WORK/lg2"
sed -i.bak 's/require_new_sha_for_rereview: true/require_new_sha_for_rereview: false/' "$WORK/lg2/.ai-collab/project.yaml" && rm -f "$WORK/lg2/.ai-collab/project.yaml.bak"
expect_failure "require_new_sha_for_rereview cannot be turned off" "require_new_sha_for_rereview must be set once, to true" verify "$WORK/lg2"
cp -r "$p" "$WORK/lg3"
sed -i.bak '/^loop_guard:/,$d' "$WORK/lg3/.ai-collab/project.yaml" && rm -f "$WORK/lg3/.ai-collab/project.yaml.bak"
expect_failure "a profile without loop_guard fails verify" "missing top-level key 'loop_guard'" verify "$WORK/lg3"
expect_failure "review-state refuses a profile without loop_guard" "missing top-level key 'loop_guard'" \
  "$KIT/scripts/verify.sh" review-state --root "$WORK/lg3" --ready "$s1"

# 8. Workflow files must parse; an invalid workflow silently produces no CI run at all.
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  for wf in "$KIT"/.github/workflows/*.yml; do
    expect_success "workflow parses: ${wf##*/}" python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$wf"
  done
else
  echo "skip - workflow YAML check (python3 with PyYAML not available; NOT verified)"
fi

echo "passed=$passed failed=$failed"
[ "$failed" -eq 0 ]
