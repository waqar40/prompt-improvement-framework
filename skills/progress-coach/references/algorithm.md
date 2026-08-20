# Algorithm & Field Glossary — what `compute-progress.py` already decided for you

Full derivation + justification: `docs/adr/0001-adaptive-personalized-progress-coaching.md`. This
file is the **skill-facing summary** — you never recompute any of this; you only interpret and
narrate the JSON `scripts/compute-progress.py` already produced. Never override a numeric field
it set; only add the text fields listed in `SKILL.md`'s output contract.

## What the script already computed, per dimension

- **`level`** (0–1) — a recency-weighted, shrinkage-smoothed estimate of how often this dimension
  scores `met`. Treat < 0.5 as a real weakness, > 0.85 as a real strength — anything between is
  "developing," not yet either.
- **`deviation`** / **`ci_low`**/`ci_high`** — how much to trust `level`. A wide band (`ci_high -
  ci_low` > ~0.3) means "not enough consistent evidence yet" — say so plainly rather than stating
  the level as settled fact.
- **`pace`** — `improving_fast` / `improving_slow` / `flat` / `regressing` / `insufficient_data`.
  This already accounts for noise (a dead-band) — **never re-eyeball the raw score history and
  second-guess this classification**; it exists specifically to stop that kind of overreaction.
- **`mastered`** — `true` only once level clears 0.85 with a trustworthy confidence bound, and
  stays `true` until level drops below 0.70 (hysteresis, so don't be alarmed by one so-so run on
  an already-mastered dimension — that's expected and by design).
- **`trustable`** — `false` means fewer than 6 real observations; never present an untrustable
  dimension's level as a settled fact — call it "too early to tell" instead.

## `focus` object — what to lead the coaching with

- **`reason: "provisional..."`** → this is a first-ever or very-early run. Say so plainly: rank
  by raw level only, no promises about pace or mastery yet, no false confidence.
- **`reason: "staying on your current focus..."`** → the user has been working this dimension
  across runs; frame this run as a continuation ("still working on X"), not a fresh diagnosis.
- **`reason: "lowest trustable, not-yet-mastered dimension"`** → the prior focus just graduated
  (check `mastered_dimensions`) or this is the first non-cold-start run; frame this as "next up."
- **`reason: "maintenance..."`** → everything trustable is mastered. Congratulate, then either
  point at the lowest-`n_obs` dimension to build more evidence, or note there's nothing urgent.
- **`escalate: true`** → `stall_runs >= 3` on the same focus with no real movement. **Do not just
  repeat the same advice a third time** — pull a *different* rule/exercise from
  `dimension-playbooks.md` for this dimension than whatever was suggested last run (check the
  prior `progress/<user>.md` if available), or suggest a concrete one-line rewrite template
  instead of general guidance.

## `regression_alerts` — always surface, independent of `focus`

Each entry means a dimension that was reliably mastered is now trending down. Report these
**separately from the main focus**, never folded silently into it — a slipping strength deserves
its own callout even while coaching stays on the primary focus dimension.

## Cold start (`cold_start: true`)

Never state a pace, a mastery claim, or a regression alert — the script already suppressed all
three for exactly this reason (not enough history to trust them). Say plainly this is a baseline
run and real trend data starts appearing from the next `/analyse` onward.
