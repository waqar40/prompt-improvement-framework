# ADR 0001 — Adaptive, Personalized Progress Coaching

**Status:** Proposed (implemented on `feat/adaptive-progress-coaching`, pending your review)
**Date:** 2026-08-21
**Deciders:** waqar.aziz (review pending) · drafted + implemented by Claude per explicit delegation ("you may decide your own, just create ADR")

## Context

Today `/analyse` scores every prompt against 14 rubric dimensions (D1–D10 design, E1–E4
evaluability), but the compiled guide (`prompt-example-curator`) is a **stateless recompute**
each run: strongest/weakest prompts as worked examples, a generic `common_gap`/`strongest_habit`
line, and static `habits_build`/`habits_have` lists. It does not:

1. Track a specific user's strengths/weaknesses **per dimension** over time (only overall score).
2. Tell them **which dimension improved, and at what pace**, between one `/analyse` run and the next.
3. **Decide what to focus on next** based on that history, rather than re-deriving generic advice
   from scratch each run.
4. Distinguish a **legitimate short-term dip** (noise, a hard task, a small sample) from a **real,
   sustained regression** worth flagging.

The user asked for this to become adaptive and personalized, acknowledged no established internal
pattern exists, and asked for research into known frameworks before deciding. Full research report
is preserved in this ADR's Alternatives section; the short version: **no single existing framework
fits directly** (they're built for different problems — trained ML models, pairwise game ratings,
binary pass/fail skills) but several contribute one reusable mechanism each.

## Decision

Build a new, deterministic-first **`progress-coach`** capability that runs after scoring, tracks
per-dimension state across `/analyse` runs, and drives what the guide recommends next. Deterministic
math lives in a testable script (`scripts/compute-progress.py`); only the human-readable coaching
text (rationale phrasing, concrete rules for the current focus) is LLM-authored, and even that
draws from a fixed reference playbook rather than improvising each time — consistent with this
repo's existing script-does-math / skill-does-judgment split (`validate-frontmatter.py`,
`render-guide.py`).

### Algorithm (deterministic, in `compute-progress.py`)

Per dimension `d`, map each scored prompt's verdict to a numeric observation
(`met=1.0, partial=0.5, gap=0.0`; `na` is dropped, not a zero). Constants (initial defaults —
tune against real data, not load-bearing on correctness):

| Constant | Value | Source |
|---|---|---|
| `LAMBDA` (EWMA weight) | 0.25 | SPC literature's 0.05–0.3 band |
| `K0` (shrinkage pseudo-count) | 2.0 | Bayesian/IRT "don't trust a tiny sample" |
| `PRIOR_MU` | 0.5 | neutral prior |
| `N_MIN` (min obs to trust a dimension) | 6 | cold-start guard |
| `MASTER_FLOOR` / `MASTER_CIGATE` | 0.85 / 0.80 | Bloom's 80–90% mastery criterion + a confidence gate so a lucky streak can't graduate a dimension |
| `DEMOTE_FLOOR` | 0.70 | Leitner-style hysteresis — mastered doesn't flip-flop every run |
| `STALL_RUNS` | 3 | anti "SM-2 low-interval hell" — same reps not working → change tactic |
| pace dead-band | `Z=1.0` SE, asymmetric `+0.12` / `−0.06` | SPC dead-band (kill n=1 noise) + regression flagged earlier than improvement is celebrated |

1. **Smoothed level** `L[d]` — EWMA over that dimension's observations, shrunk toward `PRIOR_MU`
   by `K0` pseudo-observations (Bayesian shrinkage). One bad prompt cannot read as "0% mastery."
2. **Confidence** `RD[d]` (Glicko's Rating Deviation, adapted) — standard error of `L[d]` from an
   effective sample size `N_eff = min(n, (2−λ)/λ)`; inflated when a dimension goes unexercised.
3. **Pace** — the dead-banded, asymmetric change in `L[d]` between this run's checkpoint and the
   last, classified `improving_fast` / `improving_slow` / `flat` / `regressing`. With ≥3
   checkpoints, prefer the OLS slope over the last 3 runs (smoother signal).
4. **Mastery** — Bloom floor (`≥0.85`) **and** the confidence lower-bound clears `0.80`, **and**
   pace isn't `regressing`; once mastered, only demoted below `0.70` (hysteresis).
5. **Next focus** — Theory-of-Constraints: the single lowest-level **trustable** (`n ≥ N_MIN`),
   not-yet-mastered dimension, with deterministic tie-breaks (lower level → prefer flat/regressing
   pace over improving → a fixed foundational-first `PRIORITY` order → fewer observations first).
   **Exactly one primary focus per run** — never coach multiple weaknesses simultaneously.
6. **Regression alerts** — surfaced *separately* from the focus: any dimension that was ever
   mastered and is now `regressing`, regardless of what the current focus is.
7. **Stall handling** — if the focus dimension is `flat` for `STALL_RUNS` consecutive runs,
   escalate: swap generic advice for a concrete rule/checklist from the dimension playbook (below),
   rather than repeating the same coaching.
8. **Cold start** — first-ever run (or all dimensions under `N_MIN`): no pace claims, no mastery
   claims, no regression alerts — rank by raw shrunk level only and label the focus "provisional."

Full formulas, the mastery/hysteresis state machine, and the priority tie-break order are in
`skills/progress-coach/references/algorithm.md` (mirrors this section, kept in sync).

### Schema changes (additive, backward-compatible)

`<outcomes>/scores/<user>.jsonl` gains two fields on newly-appended rows:
- `run_id`: the ISO timestamp of the `/analyse` invocation that scored this prompt — every row
  appended by one run shares the same `run_id`. This is the "checkpoint" unit pace is computed
  across (a calendar day is not reliable — the same user can run `/analyse` twice in a day, or
  skip weeks).
- `dims`: a compact `{"D1":"met","D2":"partial",...}` map (verdicts only, no evidence text —
  evidence stays in the per-file review and the guide's worked examples, keeping the store
  lightweight).

**Old rows lack both fields.** `compute-progress.py` degrades gracefully: rows without `run_id`
are bucketed by `date` as a best-effort checkpoint; rows without `dims` are excluded from
per-dimension computation entirely (they still exist in the store, just contribute nothing to
progress — no fabricated data). This is why cold-start handling matters even for existing users:
your real `waqaraziz` store from this week predates `dims`, so the very next `/analyse` run
effectively starts fresh on the progress side, correctly labeled `provisional`.

### New artifacts

- `scripts/compute-progress.py` — the deterministic engine above. Reads
  `<outcomes>/scores/<user>.jsonl` + the previous `<outcomes>/progress/<user>.json` (for mastery
  hysteresis and stall counters), writes the new `<outcomes>/progress/<user>.json`. No LLM call —
  fully unit-testable, wired into `scripts/selftest.sh`.
- `skills/progress-coach/` — reads `compute-progress.py`'s output, authors the human-readable
  rationale and the focus dimension's concrete steps/rules (drawing from
  `references/dimension-playbooks.md`, a hand-written, reusable rule set per dimension — not
  improvised per run), and renders `<outcomes>/progress/<user>.md`.
- `guides/<user>.md` gains a short **"Your Focus Right Now"** teaser (current focus + one-line
  rationale + pace + any regression alert + a pointer to the full `progress/<user>.md`) —
  `prompt-example-curator` embeds it by reading `progress-coach`'s just-computed output; it does
  not recompute anything itself.

### Pipeline order (in `prompt-journal/SKILL.md`)

```
prompt-critic (score, now emits dims per prompt)
    → append to scores/<user>.jsonl (now carries run_id + dims)
    → progress-coach (compute-progress.py, then author the plan)  ← NEW STEP
    → prompt-example-curator (whole-store examples + embeds the focus teaser)
    → asset-suggester
```

## Alternatives considered (from the research spike)

Full report is preserved by the research agent; summarized per option, with why each was or
wasn't adopted wholesale:

| Framework | Reusable piece taken | Why not adopted wholesale |
|---|---|---|
| Bayesian Knowledge Tracing | latent-mastery-with-threshold framing | fitting BKT's 4 parameters needs training data we don't have and produces a black box; we wanted an inspectable rationale |
| IRT / Bloom mastery learning | confidence-gated criterion (0.85 floor + CI gate), "correctives target the failed objective" | full IRT ability estimation is overkill for 14 discrete dimensions with no item-difficulty calibration |
| Leitner / SM-2 / FSRS | promotion/demotion hysteresis, "stuck card" stall detection, mean-reversion caution | these schedule *review timing* for memorization; we don't need a review calendar, just a state machine |
| Elo / Glicko | level + deviation (uncertainty) representation, recency weighting | pairwise rating updates don't apply — there's no opponent, just a threshold |
| EWMA / CUSUM / SPC | **the workhorse** — smoothing + dead-band pace classification | CUSUM's alarm/slack tuning is more machinery than a first version needs; EWMA covers our case |
| Deliberate practice / ZPD / periodization / Theory of Constraints | single-bottleneck focus, "change one variable at a time" | these are heuristics, not algorithms — encoded directly into the next-focus tie-break logic |
| Duolingo Half-Life Regression | confirms "per-user history should drive personalization" | it's a trained regression model; out of scope (no training data, no ML infra in this repo) |
| SonarQube "new code" leak-period gate | judge the *recent* trend, not the lifetime average | directly adopted via the EWMA recency weighting + per-run checkpoints |

**Alternative rejected: fold this into `prompt-example-curator` instead of a new skill.** Curator's
job is a stateless whole-store recompute each run; progress-coach is explicitly **stateful**
(reads its own prior output for hysteresis/stall counters). Mixing them would make curator's
output non-reproducible from the store alone, breaking its current, simpler contract. Kept as two
skills — this repo's own single-responsibility convention (mirrors the existing
reviewer/fixer/architect split).

**Alternative rejected: PDF/Word rendering for the progress plan.** The guide already has
PDF/Word via `render-guide.py`; the progress plan is Markdown-only for v1 (YAGNI) — trivial to
extend later by reusing the same reportlab/python-docx pipeline if wanted.

## Consequences

**Positive:**
- Coaching becomes genuinely personalized and adaptive instead of a generic snapshot restated
  each run.
- Every recommendation is backed by an inspectable number and a plain-English rationale — no
  black-box model to trust blindly.
- The math is deterministic and unit-tested (`selftest.sh`), independent of LLM call variance —
  the same score history always produces the same focus decision.

**Negative / risks:**
- **New complexity surface.** A new stateful file (`progress/<user>.json`) that must never be
  hand-edited or the hysteresis/stall counters desync — documented as a hard rule, same as
  "never edit the score store."
- **Constants are engineering defaults, not proven-optimal.** They're individually justified
  against a cited framework, but the specific numbers (0.25, 6, 0.85, 3, …) will want tuning once
  real multi-run data exists. Flagged explicitly, not hidden.
- **Schema migration.** Existing score-store rows (including the real `waqaraziz.jsonl` written
  this week) lack `dims`/`run_id` and won't contribute to progress tracking — correctly degrades
  to cold-start rather than fabricating history, but means the "adaptive" behavior only becomes
  visible after a couple of real `/analyse` runs post-upgrade.
- **Gameability.** A user could pad prompts to trigger `met` on every dimension. Mitigated (not
  eliminated) by D10 (structural economy) directly penalizing padding, and mastery requiring a
  *sustained* level across multiple runs, not one gamed run.

## Open questions for your review

1. Are the initial constants (mastery floor 0.85, `N_MIN=6`, `STALL_RUNS=3`, …) reasonable, or do
   you want different defaults given how often you expect to actually run `/analyse`?
2. Should the dimension `PRIORITY` tie-break order (clarity/specificity/evaluability first,
   examples/positive-framing/uncertainty last) match your own sense of what matters most, or
   would you rank differently?
3. Is a separate `progress/<user>.md` file the right shape, or would you rather the focus plan
   live entirely inside the existing guide (accepting a longer single document)?
4. Comfortable with the schema addition to the score store (`run_id`, `dims`) being permanent
   going forward, given it's additive/backward-compatible and never rewrites old rows?
