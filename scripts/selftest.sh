#!/usr/bin/env bash
# ai-gen — deterministic self-test for the prompt-journal framework's SCRIPTS + artifact schemas.
# Runs entirely in a throwaway sandbox (temp dirs, temp settings, temp journal) — it never touches
# your real ~/.claude/settings.json, the sibling prompts/ journal, or scores/guides/suggestions.
# Covers the parts that don't need the LLM: the recorder, the configurator, the header parser, and
# the guide renderer. The agent-driven skills/commands are exercised by the /test play (see
# .claude/skills/test-framework/SKILL.md), which runs this script as its first step.
#
#   bash scripts/selftest.sh
#
# Exit code: 0 if no check FAILed (SKIPs are allowed), 1 otherwise.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
FIX="$REPO/tests/fixtures"
PASS=0; FAIL=0; SKIP=0
pass(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
skip(){ echo "  [SKIP] $1"; SKIP=$((SKIP+1)); }
section(){ echo; echo "== $1 =="; }

SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
PS_EXE=""; for c in pwsh powershell; do command -v "$c" >/dev/null 2>&1 && { PS_EXE="$c"; break; }; done
HAVE_PY=0; command -v python3 >/dev/null 2>&1 && HAVE_PY=1

# ---------------------------------------------------------------------------------------------
section "recorder.sh — header, project/root, and identifier fallbacks"

# (1) non-git cwd -> identifier repo/<folder>, header carries project + root
mkdir -p "$SB/plain"; J1="$SB/j1"
printf '{"prompt":"hello world","cwd":"%s"}' "$SB/plain" | PROMPT_JOURNAL_DIR="$J1" bash "$REPO/scripts/record-prompt.sh"
f1="$J1/repo-plain.txt"
if [ -f "$f1" ]; then pass "repo/ fallback wrote $(basename "$f1")"; else fail "expected repo-plain.txt (got: $(ls "$J1" 2>/dev/null))"; fi
h1="$(head -1 "$f1" 2>/dev/null || true)"
echo "$h1" | grep -q "branch=repo/plain"      && pass "header has branch=repo/plain"      || fail "header branch wrong: $h1"
echo "$h1" | grep -q "project=plain"          && pass "header has project=plain"          || fail "header project wrong: $h1"
echo "$h1" | grep -q "root=$SB/plain ====="   && pass "header has root=<path> (last)"     || fail "header root wrong: $h1"

# (2) session fallback via CLAUDE_SESSION_NAME
mkdir -p "$SB/plain2"; J2="$SB/j2"
printf '{"prompt":"sess","cwd":"%s"}' "$SB/plain2" | PROMPT_JOURNAL_DIR="$J2" CLAUDE_SESSION_NAME="mysess" bash "$REPO/scripts/record-prompt.sh"
[ -f "$J2/session-mysess.txt" ] && pass "session/ fallback wrote session-mysess.txt" || fail "expected session-mysess.txt (got: $(ls "$J2" 2>/dev/null))"

# (3) git branch path -> identifier is the branch; project = repo folder
if command -v git >/dev/null 2>&1; then
  GR="$SB/gitrepo"; mkdir -p "$GR"; ( cd "$GR" && git init -q && git checkout -q -b feature/DEMO ) 2>/dev/null
  J3="$SB/j3"
  printf '{"prompt":"on a branch","cwd":"%s"}' "$GR" | PROMPT_JOURNAL_DIR="$J3" bash "$REPO/scripts/record-prompt.sh"
  h3="$(head -1 "$J3/feature-DEMO.txt" 2>/dev/null || true)"
  if [ -n "$h3" ]; then
    echo "$h3" | grep -q "branch=feature/DEMO" && pass "git branch -> branch=feature/DEMO" || fail "branch header wrong: $h3"
    echo "$h3" | grep -q "project=gitrepo"     && pass "git branch -> project=gitrepo"     || fail "project header wrong: $h3"
  else fail "git branch case wrote no feature-DEMO.txt (got: $(ls "$J3" 2>/dev/null))"; fi
else skip "git not on PATH — branch-resolution case"; fi

# ---------------------------------------------------------------------------------------------
section "recorder.ps1 — header parity (Windows/PowerShell)"
if [ -n "$PS_EXE" ]; then
  J4="$SB/j4"
  printf '{"prompt":"ps hello","cwd":"%s"}' "$REPO" | PROMPT_JOURNAL_DIR="$J4" "$PS_EXE" -NoProfile -File "$REPO/scripts/record-prompt.ps1"
  fp="$(ls "$J4"/*.txt 2>/dev/null | head -1)"
  hp="$(head -1 "$fp" 2>/dev/null || true)"
  echo "$hp" | grep -q "project=" && echo "$hp" | grep -q "root=" && pass "ps1 header has project + root" || fail "ps1 header missing project/root: $hp"
else skip "no pwsh/powershell — recorder.ps1 parity"; fi

# ---------------------------------------------------------------------------------------------
section "configure.sh — idempotency, stale removal, preservation, self-test"
if [ "$HAVE_PY" -eq 1 ]; then
  S="$SB/settings.json"
  cat > "$S" <<'JSON'
{ "model": "opus", "hooks": { "UserPromptSubmit": [
  { "hooks": [ { "type": "command", "command": "pwsh -File C:/old/log-prompt.ps1" } ] },
  { "hooks": [ { "type": "command", "command": "echo keep-me" } ] }
] } }
JSON
  out1="$(bash "$REPO/scripts/configure.sh" --settings "$S" 2>&1)"
  echo "$out1" | grep -q "Self-test passed" && pass "configure self-test passed" || fail "configure self-test did not pass"
  bash "$REPO/scripts/configure.sh" --settings "$S" >/dev/null 2>&1   # second run -> must dedupe
  py="$(cat "$S" | python3 -c "
import json,sys
s=json.load(sys.stdin); ups=s['hooks']['UserPromptSubmit']
rec=sum(1 for g in ups if any('record-prompt' in h['command'] for h in g['hooks']))
keep=sum(1 for g in ups if any('keep-me' in h['command'] for h in g['hooks']))
print(f'{rec} {keep} {s.get(\"model\")}')")"
  set -- $py
  [ "$1" = "1" ]     && pass "idempotent: exactly 1 recorder hook after 2 runs" || fail "recorder hook count = $1 (want 1)"
  [ "$2" = "1" ]     && pass "preserved unrelated hook (keep-me)"                || fail "unrelated hook lost"
  [ "$3" = "opus" ]  && pass "preserved unrelated key (model)"                   || fail "model key lost"
  # --journal bakes the path into the hook command
  bash "$REPO/scripts/configure.sh" --settings "$S" --journal "$SB/custom-j" >/dev/null 2>&1
  cat "$S" | python3 -c "
import json,sys
ups=json.load(sys.stdin)['hooks']['UserPromptSubmit']
cmds=[h['command'] for g in ups for h in g['hooks'] if 'record-prompt' in h['command']]
sys.exit(0 if any('custom-j' in c for c in cmds) else 1)" && pass "--journal baked into recorder hook command" || fail "--journal not baked"
else skip "no python3 — configure.sh JSON assertions"; fi

# ---------------------------------------------------------------------------------------------
section "configure.sh — guide-rendering deps are best-effort, never blocking"
if [ "$HAVE_PY" -eq 1 ]; then
  S2="$SB/settings-deps.json"
  out2="$(bash "$REPO/scripts/configure.sh" --settings "$S2" 2>&1)"
  echo "$out2" | grep -qE "^\[(OK|FIXED)\][[:space:]]+Guide PDF/Word deps|^\[FIXED\][[:space:]]+Installed pinned guide-rendering deps|^\[OPTIONAL\][[:space:]]+PDF/Word guide views need" \
    && pass "configure.sh reports guide-deps status as OK/FIXED/OPTIONAL" \
    || fail "configure.sh did not report a guide-deps status line: $out2"
  echo "$out2" | grep -qE "^\[ACTION\].*(reportlab|python-docx|guide)" \
    && fail "guide-rendering deps must never surface as a blocking [ACTION]" \
    || pass "guide-rendering deps never block configure (no [ACTION] for them)"
else skip "no python3 — configure.sh guide-deps assertions"; fi

# ---------------------------------------------------------------------------------------------
section "scripts/requirements.txt — reportlab pinned below 4.2 (Python 3.8 hashlib compat)"
REQS_FILE="$REPO/scripts/requirements.txt"
if [ -f "$REQS_FILE" ]; then
  pass "scripts/requirements.txt exists"
  if [ "$HAVE_PY" -eq 1 ]; then
    python3 - "$REQS_FILE" <<'PY' && pass "reportlab pin is <4.2 and python-docx is pinned" || fail "requirements.txt pin check failed"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'^reportlab==(\d+)\.(\d+)(?:\.\d+)?\s*$', text, re.MULTILINE)
assert m, "reportlab==X.Y not pinned in requirements.txt"
major, minor = int(m.group(1)), int(m.group(2))
assert (major, minor) < (4, 2), f"reportlab pin {major}.{minor} is not below 4.2 (needed for Python 3.8 hashlib compat)"
assert re.search(r'^python-docx==\S+\s*$', text, re.MULTILINE), "python-docx==X.Y.Z not pinned in requirements.txt"
PY
  else skip "no python3 — requirements.txt pin regex check"; fi
else fail "scripts/requirements.txt is missing"; fi

# ---------------------------------------------------------------------------------------------
section "header parser — new, spaced-root, and legacy headers"
if [ "$HAVE_PY" -eq 1 ]; then
  python3 - "$FIX/logs" <<'PY' && pass "parser handles new + spaced + legacy headers" || fail "parser rejected a header"
import re, sys, pathlib
rx = re.compile(r'^===== \[(?P<ts>.*?)\] branch=(?P<branch>\S+)(?: project=(?P<project>\S+))?(?: root=(?P<root>.+?))? =====$')
# synthetic edge: a root path containing spaces must still parse
edge = "===== [2026-08-14 10:00:00] branch=feature/x project=alpha root=C:/Program Files/My Repo ====="
assert rx.match(edge) and rx.match(edge)['root'] == 'C:/Program Files/My Repo', "spaced root failed"
n=0
for p in pathlib.Path(sys.argv[1]).glob('*.txt'):
    for line in p.read_text(encoding='utf-8').splitlines():
        if line.startswith('====='):
            assert rx.match(line), f"unparseable header in {p.name}: {line}"
            n+=1
assert n>=4, f"expected >=4 fixture headers, saw {n}"
PY
else skip "no python3 — header parser check"; fi

# ---------------------------------------------------------------------------------------------
section "render-guide.py — Markdown view incl. coverage line"
if [ "$HAVE_PY" -eq 1 ]; then
  cp "$FIX/guide-sample.json" "$SB/g.json"
  rerr="$(python3 "$REPO/scripts/render-guide.py" "$SB/g.json" --md 2>&1)"; rc=$?
  if [ $rc -ne 0 ]; then
    echo "$rerr" | grep -qiE "ModuleNotFound|ImportError|missing dependency" && skip "render-guide deps missing (reportlab/docx import) — md path" || fail "render-guide --md failed: $rerr"
  else
    grep -q "## Snapshot" "$SB/g.md" && pass "render-guide wrote Markdown with Snapshot" || fail "no Snapshot in rendered md"
    grep -q "Coverage:"   "$SB/g.md" && pass "render-guide shows the new Coverage line"  || fail "Coverage line missing from md"
  fi
else skip "no python3 — render-guide check"; fi

# ---------------------------------------------------------------------------------------------
section "recorder — skips harness task-notification machine-output"
J5="$SB/j5"
printf '{"prompt":"<task-notification><task-id>x</task-id> completed</task-notification>","cwd":"%s"}' "$SB/plain" \
  | PROMPT_JOURNAL_DIR="$J5" bash "$REPO/scripts/record-prompt.sh"
[ -z "$(ls -A "$J5" 2>/dev/null)" ] && pass "recorder.sh dropped a task-notification (nothing written)" || fail "recorder.sh logged a task-notification"
printf '{"prompt":"a real authored prompt","cwd":"%s"}' "$SB/plain" | PROMPT_JOURNAL_DIR="$J5" bash "$REPO/scripts/record-prompt.sh"
[ -n "$(ls -A "$J5" 2>/dev/null)" ] && pass "recorder.sh still logs a real prompt (control)" || fail "recorder.sh dropped a real prompt"
if [ -n "$PS_EXE" ]; then
  J6="$SB/j6"
  printf '{"prompt":"<task-notification> completed","cwd":"%s"}' "$REPO" | PROMPT_JOURNAL_DIR="$J6" "$PS_EXE" -NoProfile -File "$REPO/scripts/record-prompt.ps1"
  [ -z "$(ls -A "$J6" 2>/dev/null)" ] && pass "recorder.ps1 dropped a task-notification" || fail "recorder.ps1 logged a task-notification"
fi

# ---------------------------------------------------------------------------------------------
echo; echo "=============================================="
echo "  selftest: $PASS passed, $FAIL failed, $SKIP skipped"
echo "=============================================="
[ "$FAIL" -eq 0 ]
