#!/usr/bin/env bash
# ai-gen — deterministic self-test for the prompt-journal framework's SCRIPTS + artifact schemas.
# Runs entirely in a throwaway sandbox (temp dirs, temp settings, temp journal) — it never touches
# your real ~/.claude/settings.json, the sibling prompts/ journal, or scores/guides/suggestions.
# Covers the parts that don't need the LLM: the recorder, the configurator, the header parser, and
# the guide renderer. The agent-driven skills/commands are exercised by the /test play (see
# skills/test-framework/SKILL.md), which runs this script as its first step.
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
section "record-tool-use.sh + record-turn-end.sh — asset-use capture pipeline"
# Isolate the buffer dir (normally $TMPDIR/prompt-journal-turn) inside the sandbox so this
# section can never collide with — or leak into — a real session's buffer.
OLD_TMPDIR="${TMPDIR:-}"
export TMPDIR="$SB/hooktmp"; mkdir -p "$TMPDIR"
REPO_SIM="$SB/repo-sim"; mkdir -p "$REPO_SIM/.claude/skills/prompt-critic"
echo "fake skill" > "$REPO_SIM/.claude/skills/prompt-critic/SKILL.md"
J7="$SB/j7"

# (1) normal turn: prompt -> Skill + Edit + unresolved Task -> Stop flushes a deduped block
SIDA="selftest-sessA"
printf '{"prompt":"fix bug","cwd":"%s","session_id":"%s"}' "$REPO_SIM" "$SIDA" | PROMPT_JOURNAL_DIR="$J7" bash "$REPO/scripts/record-prompt.sh"
printf '{"session_id":"%s","tool_name":"Skill","tool_input":{"skill":"prompt-critic"}}' "$SIDA" | CLAUDE_PROJECT_DIR="$REPO_SIM" bash "$REPO/scripts/record-tool-use.sh"
printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s/src/foo.py"}}' "$SIDA" "$REPO_SIM" | CLAUDE_PROJECT_DIR="$REPO_SIM" bash "$REPO/scripts/record-tool-use.sh"
printf '{"session_id":"%s","tool_name":"Task","tool_input":{"subagent_type":"code-reviewer"}}' "$SIDA" | CLAUDE_PROJECT_DIR="$REPO_SIM" bash "$REPO/scripts/record-tool-use.sh"
printf '{"session_id":"%s","tool_name":"mcp__github__create_pull_request","tool_input":{}}' "$SIDA" | CLAUDE_PROJECT_DIR="$REPO_SIM" bash "$REPO/scripts/record-tool-use.sh"
printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"echo hi"}}' "$SIDA" | CLAUDE_PROJECT_DIR="$REPO_SIM" bash "$REPO/scripts/record-tool-use.sh"   # must be ignored (not in the whitelist)
printf '{"session_id":"%s"}' "$SIDA" | bash "$REPO/scripts/record-turn-end.sh"
fileA="$(ls "$J7"/*.txt 2>/dev/null | head -1)"
if [ -n "$fileA" ]; then
  grep -q "^----- assets-used -----$" "$fileA"          && pass "assets-used block appended"              || fail "no assets-used block in $fileA"
  grep -q "^skill: prompt-critic ->.*SKILL.md$" "$fileA" && pass "resolved skill path recorded"            || fail "skill line missing/unresolved: $(cat "$fileA")"
  grep -q "^tool: Edit ->.*src/foo.py$" "$fileA"          && pass "Edit file path recorded"                 || fail "Edit line missing: $(cat "$fileA")"
  grep -q "^subagent: code-reviewer -> (unresolved)$" "$fileA" && pass "unresolvable subagent path -> (unresolved)" || fail "subagent line wrong: $(cat "$fileA")"
  grep -q "^mcp: mcp__github__create_pull_request -> (unresolved)$" "$fileA" && pass "MCP tool call recorded" || fail "mcp line missing/wrong: $(cat "$fileA")"
  grep -q "echo hi" "$fileA"                              && fail "Bash call leaked into assets-used (must be filtered)" || pass "non-whitelisted tool (Bash) correctly excluded"
else
  fail "no journal file written for case (1)"
fi

# (2) a turn with no trackable tool use -> Stop must add nothing
SIDB="selftest-sessB"
printf '{"prompt":"hi","cwd":"%s","session_id":"%s"}' "$REPO_SIM" "$SIDB" | PROMPT_JOURNAL_DIR="$J7" bash "$REPO/scripts/record-prompt.sh"
before="$(grep -c "assets-used" "$fileA" 2>/dev/null || echo 0)"
printf '{"session_id":"%s"}' "$SIDB" | bash "$REPO/scripts/record-turn-end.sh"
after="$(grep -c "assets-used" "$fileA" 2>/dev/null || echo 0)"
[ "$before" = "$after" ] && pass "no-tool-use turn adds no assets-used block" || fail "unexpected assets-used growth ($before -> $after)"

# (3) a skipped (task-notification) prompt writes no marker; a stray tool event must not leak
SIDC="selftest-sessC"
printf '{"prompt":"<task-notification>done</task-notification>","cwd":"%s","session_id":"%s"}' "$REPO_SIM" "$SIDC" | PROMPT_JOURNAL_DIR="$J7" bash "$REPO/scripts/record-prompt.sh"
[ -f "$TMPDIR/prompt-journal-turn/$SIDC.journal" ] && fail "marker written for a skipped (task-notification) prompt" || pass "no marker written for a skipped prompt"
printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"/orphan/y.py"}}' "$SIDC" | bash "$REPO/scripts/record-tool-use.sh"
printf '{"session_id":"%s"}' "$SIDC" | bash "$REPO/scripts/record-turn-end.sh"
grep -rl "orphan/y.py" "$J7" >/dev/null 2>&1 && fail "orphaned tool call leaked into a journal file" || pass "orphaned tool call discarded without leaking"

# (4) buffer dir is empty after all three turns (marker + tools files always cleaned up)
leftover="$(ls -A "$TMPDIR/prompt-journal-turn" 2>/dev/null)"
[ -z "$leftover" ] && pass "buffer dir fully cleaned up after each turn" || fail "buffer dir has leftovers: $leftover"

# (5) PowerShell parity, if available
if [ -n "$PS_EXE" ]; then
  SIDD="selftest-sessD"
  printf '{"prompt":"ps fix bug","cwd":"%s","session_id":"%s"}' "$REPO" "$SIDD" | PROMPT_JOURNAL_DIR="$J7" "$PS_EXE" -NoProfile -File "$REPO/scripts/record-prompt.ps1"
  printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s/x.py"}}' "$SIDD" "$REPO" | "$PS_EXE" -NoProfile -File "$REPO/scripts/record-tool-use.ps1"
  printf '{"session_id":"%s"}' "$SIDD" | "$PS_EXE" -NoProfile -File "$REPO/scripts/record-turn-end.ps1"
  fileD="$(ls "$J7"/*.txt 2>/dev/null | xargs grep -l "ps fix bug" 2>/dev/null | head -1)"
  [ -n "$fileD" ] && grep -q "^tool: Edit ->.*x.py$" "$fileD" && pass "ps1 asset-use pipeline appends assets-used block" || fail "ps1 asset-use pipeline did not append a block"
else
  skip "no pwsh/powershell — record-tool-use.ps1/record-turn-end.ps1 parity"
fi

if [ -n "$OLD_TMPDIR" ]; then export TMPDIR="$OLD_TMPDIR"; else unset TMPDIR; fi

# ---------------------------------------------------------------------------------------------
section "configure.sh — idempotency, stale removal, preservation, self-test"
if [ "$HAVE_PY" -eq 1 ]; then
  S="$SB/settings.json"
  # Isolate configure.sh's own dir side effects (journal + outcomes) inside the sandbox — it
  # otherwise defaults to ~/.claude/prompt-journal/*, which must never be touched by a self-test.
  CFG_JOURNAL="$SB/cfg-journal"
  export PROMPT_OUTCOMES_DIR="$SB/cfg-outcomes"
  cat > "$S" <<'JSON'
{ "model": "opus", "hooks": { "UserPromptSubmit": [
  { "hooks": [ { "type": "command", "command": "pwsh -File C:/old/log-prompt.ps1" } ] },
  { "hooks": [ { "type": "command", "command": "echo keep-me" } ] }
] } }
JSON
  out1="$(bash "$REPO/scripts/configure.sh" --settings "$S" --journal "$CFG_JOURNAL" 2>&1)"
  echo "$out1" | grep -q "Self-test passed" && pass "configure self-test passed" || fail "configure self-test did not pass"
  bash "$REPO/scripts/configure.sh" --settings "$S" --journal "$CFG_JOURNAL" >/dev/null 2>&1   # second run -> must dedupe
  py="$(cat "$S" | python3 -c "
import json,sys
s=json.load(sys.stdin); h=s['hooks']
rec=sum(1 for g in h.get('UserPromptSubmit',[]) if any('record-prompt' in x['command'] for x in g['hooks']))
keep=sum(1 for g in h.get('UserPromptSubmit',[]) if any('keep-me' in x['command'] for x in g['hooks']))
tool=sum(1 for g in h.get('PostToolUse',[])     if any('record-tool-use' in x['command'] for x in g['hooks']))
stop=sum(1 for g in h.get('Stop',[])            if any('record-turn-end' in x['command'] for x in g['hooks']))
matcher=h.get('PostToolUse',[{}])[0].get('matcher','') if h.get('PostToolUse') else ''
print(f'{rec} {keep} {s.get(\"model\")} {tool} {stop} {matcher}')")"
  set -- $py
  [ "$1" = "1" ]     && pass "idempotent: exactly 1 recorder hook after 2 runs" || fail "recorder hook count = $1 (want 1)"
  [ "$2" = "1" ]     && pass "preserved unrelated hook (keep-me)"                || fail "unrelated hook lost"
  [ "$3" = "opus" ]  && pass "preserved unrelated key (model)"                   || fail "model key lost"
  [ "$4" = "1" ]     && pass "idempotent: exactly 1 PostToolUse recorder hook after 2 runs" || fail "PostToolUse hook count = $4 (want 1)"
  [ "$5" = "1" ]     && pass "idempotent: exactly 1 Stop recorder hook after 2 runs"        || fail "Stop hook count = $5 (want 1)"
  [ "$6" = "Skill|Task|Read|Edit|Write|NotebookEdit|mcp__.*" ] && pass "PostToolUse matcher scoped to asset-invocation tools (incl. MCP)" || fail "PostToolUse matcher wrong: $6"
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
  export PROMPT_OUTCOMES_DIR="$SB/cfg-outcomes2"
  out2="$(bash "$REPO/scripts/configure.sh" --settings "$S2" --journal "$SB/cfg-journal2" 2>&1)"
  echo "$out2" | grep -qE "^\[(OK|FIXED)\][[:space:]]+Guide PDF/Word deps|^\[FIXED\][[:space:]]+Installed pinned guide-rendering deps|^\[OPTIONAL\][[:space:]]+PDF/Word guide views need" \
    && pass "configure.sh reports guide-deps status as OK/FIXED/OPTIONAL" \
    || fail "configure.sh did not report a guide-deps status line: $out2"
  echo "$out2" | grep -qE "^\[ACTION\].*(reportlab|python-docx|guide)" \
    && fail "guide-rendering deps must never surface as a blocking [ACTION]" \
    || pass "guide-rendering deps never block configure (no [ACTION] for them)"
else skip "no python3 — configure.sh guide-deps assertions"; fi
unset PROMPT_OUTCOMES_DIR   # don't leak the sandbox override into later sections of this script

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
section "header parser — assets-used block is split from the scored prompt text"
if [ "$HAVE_PY" -eq 1 ]; then
  python3 - "$FIX/logs/feature-DEMO-1_alpha.txt" <<'PY' && pass "assets-used block correctly split from prompt text" || fail "assets-used splitting broke"
import re, sys, pathlib

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
header_rx = re.compile(r'^===== \[.*?\] branch=\S+(?: project=\S+)?(?: root=.+?)? =====$')
entries = re.split(r'(?m)^(===== .*? =====)$', text)[1:]   # alternating [header, body, header, body, ...]
bodies = [entries[i+1] for i in range(0, len(entries), 2)]

def split_assets(body):
    m = re.search(r'\n-{5} assets-used -{5}\n(.*?)\n-{5} end-assets-used -{5}\n', body, re.S)
    if not m:
        return body.strip(), []
    prompt_text = body[:m.start()].strip()
    lines = [l for l in m.group(1).splitlines() if l.strip()]
    return prompt_text, lines

with_block    = [b for b in bodies if 'assets-used' in b]
without_block = [b for b in bodies if 'assets-used' not in b]
assert len(with_block) == 2, f"expected 2 entries with an assets-used block, saw {len(with_block)}"
assert len(without_block) >= 1, "expected at least 1 entry with no assets-used block (the common case)"

prompt_text, assets = split_assets(with_block[1])   # the "now push it" entry
assert prompt_text == "now push it", f"prompt text not cleanly split: {prompt_text!r}"
assert assets == ["skill: commit-message -> skills/commit-message/SKILL.md"], f"assets lines wrong: {assets}"
assert "-----" not in prompt_text, "delimiter leaked into scored prompt text"

# an entry with no block must still parse with an empty assets list and untouched prompt text
prompt_text2, assets2 = split_assets(without_block[0])
assert assets2 == [], f"expected no assets for a block-less entry, got {assets2}"
assert prompt_text2, "prompt text must not be empty for a block-less entry"
PY
else skip "no python3 — assets-used splitting check"; fi

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
section "compute-progress.py — cold-start, mastery graduation, and regression alerts"
if [ "$HAVE_PY" -eq 1 ]; then
  PF="$FIX/progress"
  python3 "$REPO/scripts/compute-progress.py" "$PF/scores-run1.jsonl" --user t --out "$SB/p1.json" >/dev/null 2>&1
  python3 - "$SB/p1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["cold_start"] is True
assert d["dimensions"]["D7"]["mastered"] is False, "must not claim mastery during cold_start"
assert d["focus"]["dimension"] == "D5" and d["focus"]["provisional"] is True
PY
  [ $? -eq 0 ] && pass "run1 (cold start): no mastery claims, focus=D5, provisional" || fail "run1 cold-start assertions failed"

  python3 "$REPO/scripts/compute-progress.py" "$PF/scores-through-run2.jsonl" --user t --prev "$SB/p1.json" --out "$SB/p2.json" >/dev/null 2>&1
  python3 - "$SB/p2.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["cold_start"] is False
assert d["dimensions"]["D7"]["mastered"] is True, "D7 (all-met both checkpoints) should graduate"
assert d["focus"]["dimension"] == "D5", "focus should stick to D5 (momentum rule)"
assert d["regression_alerts"] == [], "nothing should regress yet"
PY
  [ $? -eq 0 ] && pass "run2: D7 masters, focus stays D5, no regressions yet" || fail "run2 mastery/focus assertions failed"

  python3 "$REPO/scripts/compute-progress.py" "$PF/scores-through-run3.jsonl" --user t --prev "$SB/p2.json" --out "$SB/p3.json" >/dev/null 2>&1
  python3 - "$SB/p3.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["dimensions"]["D7"]["mastered"] is False, "D7 crashed to gap -> demoted"
assert len(d["regression_alerts"]) == 1 and d["regression_alerts"][0]["dimension"] == "D7", d["regression_alerts"]
assert d["focus"]["dimension"] == "D5", "focus must not have been disturbed by D7's regression"
PY
  [ $? -eq 0 ] && pass "run3: exactly 1 regression alert (D7), focus undisturbed (D5)" || fail "run3 regression-alert assertions failed"

  # Idempotent/deterministic: same input -> byte-identical numeric fields, twice in a row
  python3 "$REPO/scripts/compute-progress.py" "$PF/scores-through-run3.jsonl" --user t --prev "$SB/p2.json" --out "$SB/p3b.json" >/dev/null 2>&1
  diff -q "$SB/p3.json" "$SB/p3b.json" >/dev/null 2>&1 && pass "deterministic: re-running on identical inputs is byte-identical" || fail "compute-progress.py is non-deterministic"
else skip "no python3 — compute-progress.py checks"; fi

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
