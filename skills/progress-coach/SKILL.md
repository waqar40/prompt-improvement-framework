---
name: progress-coach
description: Use as a step inside the /analyse pipeline (after scoring, before prompt-example-curator) to turn a user's score history into an adaptive, personalized coaching plan — identifies the current strongest/weakest rubric dimensions, tracks pace of improvement between /analyse runs, decides the single next focus dimension (Theory-of-Constraints style, one habit at a time), and gives concrete steps/rules to practice it. All numbers come from the deterministic scripts/compute-progress.py; this skill only authors the human-readable rationale and picks concrete advice from a fixed playbook. Never invoked standalone by a user — always run via prompt-journal's pipeline. See docs/adr/0001-adaptive-personalized-progress-coaching.md for the full design.
---

# Progress Coach

Turn `<outcomes>/scores/<user>.jsonl` into `<outcomes>/progress/<user>.json` (+ a rendered
`progress/<user>.md`) — the adaptive layer on top of the stateless guide. **You compute nothing
numeric yourself.** `scripts/compute-progress.py` already did the EWMA smoothing, pace
classification, mastery gating, and next-focus selection (algorithm + justification:
`docs/adr/0001-adaptive-personalized-progress-coaching.md`). Your job is to read that output,
understand what it means (`references/algorithm.md`), and author the plain-English rationale and
concrete improvement steps (`references/dimension-playbooks.md`) — text only, never numbers.

## References
| File | Contents |
|---|---|
| `references/algorithm.md` | Field-by-field glossary of what `compute-progress.py` already decided — read this before writing a word of coaching text. |
| `references/dimension-playbooks.md` | The concrete rule(s)/exercise(s) per dimension — pick from here, don't improvise. |
| `../prompt-critic/references/rubric.md` | The dimension definitions themselves, for citing real evidence in the rationale. |

## Inputs
- `scores_path` (required): `<outcomes>/scores/<user>.jsonl`.
- `user` (required).
- `prev_progress_path` (optional): `<outcomes>/progress/<user>.json` from the last run, if it
  exists — carries mastery hysteresis and stall counters forward. Omit on a genuinely first run.
- `out_dir` (required): `<outcomes>/progress/`.

## Workflow

### Step 1 — Run the deterministic engine
Run `python3 scripts/compute-progress.py <scores_path> --user <user> [--prev <prev_progress_path>] --out <out_dir>/<user>.json`.
This is the ONLY source of every numeric field (`level`, `deviation`, `pace`, `mastered`, `focus`,
`regression_alerts`, `state`). If it exits non-zero (e.g. missing score store), stop and report —
never fabricate a progress file by hand.

### Step 2 — Read and understand the output
Read the written `<out_dir>/<user>.json` and `references/algorithm.md` together. Note
`cold_start`, the `focus` object's `reason`/`escalate`, every entry in `regression_alerts`, and
`mastered_dimensions`. If `focus.dimension` is `null` (no data at all yet), skip to Step 4 with a
plain "not enough data yet" message — do not invent a focus.

### Step 3 — Author the human-facing text (the only thing you write)
Add exactly these fields, and no others, without touching any field the script wrote:
- `focus.rationale`: 1–3 sentences, plain English, citing the actual `level`/`pace`/`n_obs` numbers
  and — where available — a real recent prompt excerpt from the score store as evidence (never
  invented). Follow `algorithm.md`'s guidance for the specific `reason` value.
- `focus.concrete_steps`: 1–2 items pulled (and lightly adapted to the user's own evidence) from
  `dimension-playbooks.md`'s entry for `focus.dimension`. If `escalate: true`, these MUST differ
  from whatever was suggested last run (check the previous `progress/<user>.md` if present).
- Per `regression_alerts[i]`: add a `note` field — one sentence naming what slipped and by how much.
- A top-level `summary`: 2–4 sentences for the guide's teaser (Step 5).

### Step 4 — Render `<outcomes>/progress/<user>.md`
Sections, in order: **Where you stand** (one line per dimension: label, level as a rounded
percentage, pace, mastered ✓/—), **Regression alerts** (if any — omit the section entirely if
empty, never print "none"), **Your focus right now** (dimension, rationale, concrete steps),
**Mastered** (list, or "none yet" only on a non-cold-start run). On `cold_start`, replace the
whole thing with a short baseline note per `algorithm.md`'s cold-start guidance.

### Step 5 — Hand back the teaser for the guide
Return `{dimension, one_line: "<label> — <first clause of rationale>", pace, regression_count}`
for `prompt-example-curator` to embed as "Your Focus Right Now" — it does not re-derive this
itself.

## Output contract
`<outcomes>/progress/<user>.json` = the script's output + only `focus.rationale`,
`focus.concrete_steps`, `regression_alerts[].note`, and top-level `summary`. Every other key is
byte-identical to what Step 1 wrote — a diff against the script's raw output must show only
additions, never a changed number.

## Constraints
- NEVER compute, adjust, or override a numeric field (`level`, `deviation`, `pace`, `mastered`,
  `delta`, `stall_runs`, anything in `state`) — those come only from `compute-progress.py`.
- NEVER coach more than one primary focus dimension in a single run — that's the whole point of
  the bottleneck rule; resist the temptation to also mention the second-weakest.
- ALWAYS pull concrete steps from `dimension-playbooks.md`; never invent generic advice
  ("write clearer prompts") the playbook doesn't back.
- ALWAYS cite real evidence (an actual prompt excerpt, an actual number) — never a fabricated example.
- On `escalate: true`, ALWAYS vary the concrete steps from the prior run — repeating identical
  advice on a stalled dimension is the exact failure mode this design exists to avoid.
- NEVER run standalone against a user's data without `prompt-journal` having just appended this
  run's scored rows — progress tracking on stale/partial data produces a misleading focus.
- Verification: given the two-checkpoint fixture in `tests/fixtures/progress/` (see
  `scripts/selftest.sh`), the rendered `progress.md` must name the correct focus dimension, must
  not claim mastery during a `cold_start` run, and must surface exactly one regression alert when
  the fixture plants one — no more, no fewer.
