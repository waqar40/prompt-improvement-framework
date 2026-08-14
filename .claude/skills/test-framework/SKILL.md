---
name: test-framework
description: Use to end-to-end TEST this prompt-journal framework — the /test play. Runs the deterministic script harness, then drives every key skill and command (prompt-critic, prompt-journal/analyse with all its selectors, prompt-example-curator, asset-suggester, asset-architect) over fixtures in an isolated sandbox and checks each outcome, reporting PASS/FAIL per step. Everything runs under the throwaway user "_selftest" and temp dirs, and is cleaned up — it never touches your real journal, scores, guide, or settings. Triggers include "test the framework", "run the framework tests", "self-test", "run the test play", "verify the pipeline works", and the /test command.
---

# Framework Test Play

Exercise the whole framework and report a PASS/FAIL checklist. **Isolation is mandatory**: use
the throwaway user `_selftest`, read fixtures from `tests/fixtures/`, and send ALL pipeline outputs
to a **temp sandbox outcomes dir** by setting `PROMPT_OUTCOMES_DIR=<a fresh temp dir>` for the run
(call it `<sbout>`). **Tear everything down at the end.** Never touch the real journal (`../prompts`),
the real outcomes dir (`../prompts-review-outcomes`), or the real `~/.claude/settings.json`.

Report each step as `[PASS] <what>` / `[FAIL] <what, and the evidence>`; end with a tally and an
overall verdict. Stop and report if Step 1 (the deterministic harness) fails — the scripts are
the foundation.

## Fixtures (input)
`tests/fixtures/logs/` — `feature-DEMO-1_alpha.txt` (project `alpha`; a 3-turn chain: a strong
spec, a vague "make it work", a terse "now push it"), `feature-DEMO-2_beta.txt` (project `beta`;
"commit this" / "version-control it"), and `legacy-no-branch.txt` (old header, no project/root).
`tests/fixtures/guide-sample.json` — a minimal guide for the renderer.

## Workflow

### Step 1 — Deterministic script harness
Run `bash scripts/selftest.sh`. **Require exit 0** (recorder header + fallbacks, configure
idempotency/self-test/--journal, header parser, renderer). Relay its PASS/FAIL tally. If it
fails, stop and report.

### Step 2 — prompt-critic (scoring contract)
Invoke **`prompt-critic`** on the strong fixture prompt and separately on `make it work`
(passing the earlier turn as `session_context`). PASS if each returns the JSON contract with a
numeric `score`, a `verdict`, and `suggested_eval_criteria`; and the vague one scores clearly
lower / flags a D1 success-criteria gap. This proves the rubric + chain handling.

### Step 3 — /analyse over ALL fixtures (default behaviour)
Run the **`prompt-journal`** pipeline with `path = tests/fixtures/logs`, `user = _selftest`, and
`PROMPT_OUTCOMES_DIR=<sbout>` so every output lands in the temp sandbox. Check the four outcomes:
- `<sbout>/scores/_selftest.jsonl` exists, one row per fixture prompt, rows carry `project` + `root`
  (and `project` is `unknown`/empty for the legacy log — graceful degradation).
- `<sbout>/reviews/_selftest/<branch>.md` exists **per file**, each with Strengths, Weaknesses, and
  an **Asset opportunities** section (the per-file outcome).
- `<sbout>/guides/_selftest.json` exists and its `snapshot.coverage` lists ≥2 projects — i.e. the
  guide is compiled across all files, not one.
- `<sbout>/suggestions/_selftest.json` exists.

### Step 4 — Selectors (project / branch / file)
Re-run the pipeline three ways and confirm narrowing works (idempotent — no double-count):
- `--project alpha` → only alpha's file is (re)processed; no `beta` rows added.
- `--branch feature/DEMO-2_beta` → only that branch's file.
- a single file path (`.../legacy-no-branch.txt`) → only that file.

### Step 5 — asset-suggester (machine-readable candidates)
Confirm `<sbout>/suggestions/_selftest.json` clustered the recurring version-control intent
(`commit this` + `version-control it` + `now push it`) into a candidate, and that the candidate
is **machine-readable**: it has `type`, `evidence` (with `source`/`project`), `target_project`
(name/root_path/branches from the headers), and `grounding` fields per the schema.

### Step 6 — asset-architect (trace + draft-only, approval gate)
Invoke **`asset-architect`** on that `_selftest` candidate with `target_repo` = a throwaway
sandbox repo you create in temp (add a tiny `CLAUDE.md` + a `.claude/rules/` so there is real
grounding to read). PASS if it: resolves/traces the target repo, reads its `CLAUDE.md`/rules,
picks a type + placement, and **presents a draft WITHOUT writing any file** (the Step 4→5
approval gate). **Do not approve** — assert no asset file was created. This proves the
agent-role behaviour and the safety gate.

### Step 7 — /catalog
Invoke the **`catalog`** skill. PASS if it reconciles against `.claude/` on disk and lists the
commands + skills (including `/test`) with usage/input/outcome.

### Step 8 — Teardown + report
Delete the temp sandbox outcomes dir `<sbout>` and every other temp dir / sandbox repo you made.
(Because all outputs went to `<sbout>`, the real outcomes dir was never touched — nothing to clean
there.) Print the PASS/FAIL checklist, the counts, and an overall verdict. Confirm no real files changed.

## Constraints
- NEVER use a real username — everything is `_selftest`; NEVER analyse the real `../prompts`.
- ALWAYS point `PROMPT_OUTCOMES_DIR` at a temp `<sbout>` so outputs never land in the real
  `../prompts-review-outcomes`; NEVER write `_selftest` artifacts into the real outcomes dir.
- NEVER approve the asset-architect draft (Step 6 stays draft-only) and NEVER let it write assets.
- NEVER edit the real `~/.claude/settings.json`; configure is tested only via `selftest.sh`'s sandbox.
- ALWAYS tear down `<sbout>` and temp dirs, even if a step fails (report what remained).
- Keep it idempotent — re-running the play must leave the repo (and the real outcomes dir) unchanged.
