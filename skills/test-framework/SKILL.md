---
name: test-framework
description: Use to end-to-end TEST this prompt-journal framework — the /test play. Runs the deterministic script harness, then drives every key skill and command (prompt-critic, prompt-journal/analyse with all its selectors, progress-coach, prompt-example-curator, asset-suggester, asset-architect, artifact-reviewer, asset-fixer) over fixtures in an isolated sandbox and checks each outcome, reporting PASS/FAIL per step. Everything runs under the throwaway user "_selftest" and temp dirs, and is cleaned up — it never touches your real journal, scores, guide, or settings. Triggers include "test the framework", "run the framework tests", "self-test", "run the test play", "verify the pipeline works", and the /test command.
---

# Framework Test Play

Exercise the whole framework and report a PASS/FAIL checklist. **Isolation is mandatory**: use
the throwaway user `_selftest`, read fixtures from `tests/fixtures/`, and send ALL pipeline outputs
to a **temp sandbox outcomes dir** by setting `PROMPT_OUTCOMES_DIR=<a fresh temp dir>` for the run
(call it `<sbout>`). **Tear everything down at the end.** Never touch the real journal
(`~/.claude/prompt-journal/prompts`), the real outcomes dir
(`~/.claude/prompt-journal/prompts-review-outcomes`), or the real `~/.claude/settings.json`.

Report each step as `[PASS] <what>` / `[FAIL] <what, and the evidence>`; end with a tally and an
overall verdict. Stop and report if Step 1 (the deterministic harness) fails — the scripts are
the foundation.

## Fixtures (input)
`tests/fixtures/logs/` — `feature-DEMO-1_alpha.txt` (project `alpha`; a 3-turn chain: a strong
spec with no assets-used block, a vague "make it work" followed by a `tool: Read` block — no
Edit/Write, evidence for a gap — and a terse "now push it" followed by a `skill: commit-message`
block), `feature-DEMO-2_beta.txt` (project `beta`; "commit this" / "version-control it"), and
`legacy-no-branch.txt` (old header, no project/root, no assets-used block — the pre-feature
common case). `tests/fixtures/guide-sample.json` — a minimal guide for the renderer.
`tests/fixtures/assets/bad-skill/SKILL.md` — a deliberately defective skill: an invalid
`argument-hint` frontmatter key (mechanical), a dangling `references/missing.md` row (mechanical,
G6), a vague description (needs authoring, G2), and no Constraints/verification (needs authoring,
Section F) — do not "fix" this file directly; it's test data for Steps 8-9.
`tests/fixtures/progress/` — three cumulative score-store snapshots (`scores-run1.jsonl`,
`scores-through-run2.jsonl`, `scores-through-run3.jsonl`) for the same synthetic user: D5 stays
weak/flat throughout, D7 is `met` every prompt through run2 (masters) then crashes to `gap` in
run3 (regresses) — deterministic math already proven by `selftest.sh`; test data for Step 5.

## Workflow

### Step 1 — Deterministic script harness
Run `bash scripts/selftest.sh`. **Require exit 0** (recorder header + fallbacks, configure
idempotency/self-test/--journal, header parser, renderer). Relay its PASS/FAIL tally. If it
fails, stop and report.

### Step 2 — prompt-critic (scoring contract + assets_used context)
Invoke **`prompt-critic`** on the strong fixture prompt and separately on `make it work`
(passing the earlier turn as `session_context`, and this turn's `assets_used: ["tool: Read ->
.../deploy.sh"]` from the fixture's assets-used block). PASS if each returns the JSON contract
with a numeric `score`, a `verdict`, `suggested_eval_criteria`, and an `execution_context`; the
vague one scores clearly lower / flags a D1 or E1 gap, and its `execution_context.consistency_note`
notes the read-only tool use as corroborating evidence (not a separate penalty — the score gap
must trace to a rubric dimension, not to "assets_used looked wrong"). Also invoke it on the
strong fixture prompt with `assets_used: []` (its real, block-less case) and confirm
`execution_context` comes back empty/inapplicable rather than fabricated. This proves the rubric
+ chain handling + assets_used-as-context (never as a score input).

### Step 3 — /analyse over ALL fixtures (default behaviour)
Run the **`prompt-journal`** pipeline with `path = tests/fixtures/logs`, `user = _selftest`, and
`PROMPT_OUTCOMES_DIR=<sbout>` so every output lands in the temp sandbox. Check the six outcomes:
- `<sbout>/scores/_selftest.jsonl` exists, one row per fixture prompt, rows carry `project` + `root`
  (and `project` is `unknown`/empty for the legacy log — graceful degradation), a `run_id` shared
  by every row this run wrote, a `dims` map (per prompt-journal's Step 2), and `assets_used`
  (non-empty for the "make it work"/"now push it" rows, `[]` for every other row — most rows,
  matching the fixture).
- `<sbout>/reviews/_selftest/<branch>.md` exists **per file**, each with Strengths, Weaknesses, and
  an **Asset opportunities** section (the per-file outcome) — grounded in `assets_used` where present.
- `<sbout>/progress/_selftest.json` exists (this run's `prompt-journal` Step 5 wiring produced it
  automatically, not a standalone invocation) — a light connectivity check; Step 5 below exercises
  the skill's actual behavior in depth against the dedicated fixture.
- `<sbout>/guides/_selftest.json` exists and its `snapshot.coverage` lists ≥2 projects — i.e. the
  guide is compiled across all files, not one.
- `<sbout>/suggestions/_selftest.json` exists.
- No `assets-used`/`----- end-assets-used -----` delimiter text leaked into any `prompt_excerpt`
  in the score store — confirms Step 1's parsing split held through the real pipeline.

### Step 4 — Selectors (project / branch / file)
Re-run the pipeline three ways and confirm narrowing works (idempotent — no double-count):
- `--project alpha` → only alpha's file is (re)processed; no `beta` rows added.
- `--branch feature/DEMO-2_beta` → only that branch's file.
- a single file path (`.../legacy-no-branch.txt`) → only that file.

### Step 5 — progress-coach (adaptive focus — the LLM-authored layer)
The deterministic math (`compute-progress.py`) is proven by `selftest.sh`; this step exercises
what the **skill** adds on top. Copy `tests/fixtures/progress/` into `<sbout>` (never point the
skill at the checked-in fixture path directly). Invoke **`progress-coach`** three times in
sequence, feeding each prior run's `progress/_selftest.json` as `prev_progress_path` to the next
— exactly like Step 1–3 of `scripts/compute-progress.py`'s `selftest.sh` section:
1. `scores-run1.jsonl`, no `--prev` → PASS if `progress/_selftest.md` states this is a baseline
   (no pace/mastery claims) and the focus is D5, marked provisional.
2. `scores-through-run2.jsonl`, `--prev` = run 1's output → PASS if D7 appears as mastered and
   the rendered plan's concrete steps for D5 are pulled from `dimension-playbooks.md` (not
   generic invented advice).
3. `scores-through-run3.jsonl`, `--prev` = run 2's output → PASS if exactly one regression alert
   (D7) appears, **separately** from the D5 focus section, with a one-sentence `note`.
For each run, diff the skill's `progress/_selftest.json` against a fresh
`compute-progress.py` run on the same inputs — PASS only if every numeric field is byte-identical
and the only differences are the added text fields (`focus.rationale`, `focus.concrete_steps`,
`regression_alerts[].note`, `summary`) per the skill's output contract.

### Step 6 — asset-suggester (machine-readable candidates)
Confirm `<sbout>/suggestions/_selftest.json` clustered the recurring, text-only version-control
intent (`commit this` + `version-control it`, both with no `assets_used`) into a candidate, and
that the candidate is **machine-readable**: it has `type`, `evidence` (with `source`/`project`),
`target_project` (name/root_path/branches from the headers), and `grounding` fields per the
schema. **`now push it` must NOT be folded into this candidate** — its `assets_used` shows an
existing `commit-message` skill was already invoked for that need, which is evidence it's
already covered, not a gap to raise a new candidate for. This proves `assets_used` actually
changes clustering behavior, not just informs it.

### Step 7 — asset-architect (trace + draft-only, approval gate)
Invoke **`asset-architect`** on that `_selftest` candidate with `target_repo` = a throwaway
sandbox repo you create in temp (add a tiny `CLAUDE.md` + a `.claude/rules/` so there is real
grounding to read). PASS if it: resolves/traces the target repo, reads its `CLAUDE.md`/rules,
picks a type + placement, and **presents a draft WITHOUT writing any file** (the Step 4→5
approval gate). **Do not approve** — assert no asset file was created. This proves the
agent-role behaviour and the safety gate.

### Step 8 — artifact-reviewer (Section G + fixed/needs-authoring labels)
Copy `tests/fixtures/assets/bad-skill/` into a scratch dir inside `<sbout>` (never review it in
place — it's checked-in test data). Invoke **`artifact-reviewer`** on the copy. PASS if the result
is `gate: FAIL` and includes, at minimum: a `blocking` finding for the invalid `argument-hint` key,
a finding for the dangling `references/missing.md` row (G6), a finding for the vague description
(G2), and a finding for the missing Constraints/verification (Section F) — with the first two
labeled `mechanical` and the last two labeled needs-authoring (per Step 3 of
`artifact-reviewer/SKILL.md`). Confirm it wrote nothing (still read-only).

### Step 9 — asset-fixer (applies mechanical, skips the rest)
Invoke **`asset-fixer`** on the same scratch copy with Step 8's findings. PASS if: the
`argument-hint` line is gone and the dangling `references/` row is gone (re-run
`scripts/validate-frontmatter.py` on the scratch copy — the ERROR must be gone), the vague
description and the missing-Constraints finding are **unchanged** and reported as `SKIPPED (not
auto-fixable)`, and no line outside what Step 8 cited was touched (diff the scratch copy against
the original fixture — only the two mechanical lines/rows differ).

### Step 10 — /catalog
Invoke the **`catalog`** skill. PASS if it reconciles against `commands/`/`skills/`/`agents/` on
disk and lists the commands + skills (including `/test`, `/fix-asset`) with usage/input/outcome.

### Step 11 — Teardown + report
Delete the temp sandbox outcomes dir `<sbout>` and every other temp dir / sandbox repo you made.
(Because all outputs went to `<sbout>`, the real outcomes dir was never touched — nothing to clean
there.) Print the PASS/FAIL checklist, the counts, and an overall verdict. Confirm no real files changed.

## Constraints
- NEVER use a real username — everything is `_selftest`; NEVER analyse the real journal dir
  (`~/.claude/prompt-journal/prompts`).
- ALWAYS point `PROMPT_OUTCOMES_DIR` at a temp `<sbout>` so outputs never land in the real
  outcomes dir (`~/.claude/prompt-journal/prompts-review-outcomes`); NEVER write `_selftest`
  artifacts into the real outcomes dir.
- NEVER approve the asset-architect draft (Step 6 stays draft-only) and NEVER let it write assets.
- NEVER edit the real `~/.claude/settings.json`; configure is tested only via `selftest.sh`'s sandbox.
- ALWAYS tear down `<sbout>` and temp dirs, even if a step fails (report what remained).
- Keep it idempotent — re-running the play must leave the repo (and the real outcomes dir) unchanged.
