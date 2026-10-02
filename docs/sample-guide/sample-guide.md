# Prompting Guide - sample

_Last updated 2026-10-02. Built from prompt-critic reviews of the journal logs._

## Snapshot
- Prompts reviewed: 7 (excellent 3 / good 1 / bad 3) - source: `SAMPLE — generic example prompts, not real data`
- Trend vs. last update: first checkpoint — no trend yet (a real guide shows improving/flat/regressing once you have 2+ /analyse runs)
- Most common gap: **E1 (success is defined) — the most frequent gap in this sample**
- Strongest habit: **D9/D10 (decomposition fit, structural economy) — met on every applicable prompt**
- Coverage: 3 files across projects [alpha, beta, example-project] (2026-08-09 → 2026-08-11)

## Your Focus Right Now
- **E1 Success is defined** (provisional — still building a baseline): E1 (success is defined) sits at level 0.45 across 5 observations, the lowest of any dimension with real evidence
- Pace: insufficient_data
- Full per-dimension plan: `progress/sample.md`

_Each prompt below has a **rubric scorecard** (Met / Partial / Missing / n-a per dimension; the score is the weighted roll-up of the applicable rows) and a **transformation table** (each gap -> a concrete rewrite + the principle it teaches)._

## What excellent looks like

### Spec + exact output format + testable acceptance line - band: excellent, score 100 (STRONG)
> Add a `--dry-run` flag to scripts/deploy.sh that prints each command it would run, prefixed with "[dry-run]", and exits 0 without executing anything. Acceptance: `bash scripts/deploy.sh --dry-run` makes no network calls and prints one line per docker/kubectl command.

_Source: `SAMPLE — generic example prompts, not real data` &middot; 2026-08-10 &middot; one_shot_

- **Why it lands here:** Names the exact file and flag (D1/D2), pins the output shape (D3), and closes with a binary acceptance line (E1/E2) that also anticipates the main failure mode (E4).

**Rubric scorecard**

| Rubric dimension | Status | Why (evidence) |
|---|---|---|
| D1 Clarity & explicitness | Met | led by the action verb 'Add'; one unambiguous instruction |
| D2 Specificity & constraints | Met | scope is scripts/deploy.sh; boundary 'without executing anything' is explicit |
| D3 Output format & length | Met | '[dry-run]' prefix + one line per command pins the shape |
| D4 Context & motivation | - | the why wouldn't change the implementation |
| D5 Grounding / reference | - | agent can read deploy.sh directly |
| D6 Examples (show-not-tell) | - | format fully described without an example |
| D7 Positive framing | Met | every instruction says what TO do |
| D8 Uncertainty handling | - | verifiable coding task, no hallucination risk |
| D9 Decomposition fit | Met | simple enough for one prompt |
| D10 Structural economy | Met | no over-engineering, no dead instructions |
| E1 Success is defined | Met | the acceptance line defines correct output |
| E2 Criteria are measurable | Met | 'makes no network calls and prints one line per ... command' is binary |
| E3 Multidimensional coverage | Met | covers both correctness (no execution) and format (prefix, one line each) |
| E4 Failure modes anticipated | Met | 'exits 0 without executing anything' guards the main failure mode |

_No changes needed - imitate this one._

### Terse chain step, correctly so - band: excellent, score 88 (STRONG)
> now push it

_Source: `SAMPLE — generic example prompts, not real data` &middot; 2026-08-10 &middot; chain_step_

- **Why it lands here:** The referent ('it') and action resolve cleanly from the session; brevity here is correct, not under-specification.
- **Chain step:** Follows the dry-run-flag spec and 'make it work' in the same session — 'it' resolves to the change just worked on.

**Rubric scorecard**

| Rubric dimension | Status | Why (evidence) |
|---|---|---|
| D1 Clarity & explicitness | Met | 'it' resolves via session context; the verb (push) is unambiguous |
| D2 Specificity & constraints | - | a push has no extra constraints to state beyond the inherited branch |
| D3 Output format & length | - | no output format applies to a git push |
| D4 Context & motivation | - | motivation wouldn't change the action |
| D5 Grounding / reference | - | no external grounding needed |
| D6 Examples (show-not-tell) | - | no example needed |
| D7 Positive framing | - | too short to carry a framing signal either way |
| D8 Uncertainty handling | - | not a factual-risk task |
| D9 Decomposition fit | Met | a single step, not artificially split |
| D10 Structural economy | Met | appropriately terse for a chain step |
| E1 Success is defined | Met | success = the push completes against the current branch, inherited from context |
| E2 Criteria are measurable | Partial | doesn't state how the push's success would be confirmed (e.g. check the command's exit status) |
| E3 Multidimensional coverage | - | a single quality axis (did it push) is at stake |
| E4 Failure modes anticipated | - | no new failure mode beyond a normal git push |

_No changes needed - imitate this one._

### One-word continuation, fully resolved by context - band: excellent, score 100 (STRONG)
> ok continue

_Source: `SAMPLE — generic example prompts, not real data` &middot; 2026-08-09 &middot; chain_step_

- **Why it lands here:** A pure continuation acknowledgment that the session fully resolves — proof that a short chain step can be excellent, not just acceptable.
- **Chain step:** Follows 'where are we' in the same session; 'continue' carries the standing task forward with no new ambiguity.

**Rubric scorecard**

| Rubric dimension | Status | Why (evidence) |
|---|---|---|
| D1 Clarity & explicitness | Met | resolves cleanly to continuing whatever was just discussed |
| D2 Specificity & constraints | - | no new constraint is introduced by a continuation |
| D3 Output format & length | - | no output format applies |
| D4 Context & motivation | - | n/a for a continuation |
| D5 Grounding / reference | - | n/a |
| D6 Examples (show-not-tell) | - | n/a |
| D7 Positive framing | - | too short to carry a framing signal either way |
| D8 Uncertainty handling | - | n/a |
| D9 Decomposition fit | Met | single step, not split |
| D10 Structural economy | Met | exactly as long as it needs to be |
| E1 Success is defined | - | a continuation inherits whatever success condition the standing task already had |
| E2 Criteria are measurable | - | n/a |
| E3 Multidimensional coverage | - | n/a |
| E4 Failure modes anticipated | - | n/a |

_No changes needed - imitate this one._

## Good, one fix away

### Clear question, missing the one anchor - band: good, score 73 (ADEQUATE)
> where are we

_Source: `SAMPLE — generic example prompts, not real data` &middot; 2026-08-09 &middot; one_shot_

- **Why it lands here:** A reasonable status check, but it doesn't name which thread or artifact it's asking about.

**Rubric scorecard**

| Rubric dimension | Status | Why (evidence) |
|---|---|---|
| D1 Clarity & explicitness | Partial | clear intent (status check) but no named thread/artifact |
| D2 Specificity & constraints | Partial | no scope given for which work this covers |
| D3 Output format & length | - | no output format needed for a status answer |
| D4 Context & motivation | - | n/a |
| D5 Grounding / reference | - | n/a |
| D6 Examples (show-not-tell) | - | n/a |
| D7 Positive framing | Met | neutral, non-prohibitive phrasing |
| D8 Uncertainty handling | - | n/a |
| D9 Decomposition fit | Met | single ask, not split |
| D10 Structural economy | Met | appropriately brief |
| E1 Success is defined | - | an informational question has no 'correct output' beyond an honest status answer |
| E2 Criteria are measurable | - | n/a |
| E3 Multidimensional coverage | - | n/a |
| E4 Failure modes anticipated | - | n/a |

**Transformation - turn each gap into a rewrite**

| Rubric | You wrote | Best-practice rewrite | Principle |
|---|---|---|---|
| D1 | where are we | where are we on the --dry-run flag work for scripts/deploy.sh? | Name the thread/artifact even in a quick status check so the answer can't drift to the wrong topic. |

- **Full rewritten prompt:** _where are we on the --dry-run flag work for scripts/deploy.sh?_

## Anti-patterns to kill

### Vague success word after a fully-specified task - band: bad, score 65 (WEAK)
> make it work

_Source: `SAMPLE — generic example prompts, not real data` &middot; 2026-08-10 &middot; chain_step_

- **Why it lands here:** 'it' resolves fine from context, but 'work' restates no success condition even though the prior turn already had one — leaving it unstated whether that acceptance line still applies.
- **Chain step:** Follows the --dry-run-flag spec in the same session.

**Rubric scorecard**

| Rubric dimension | Status | Why (evidence) |
|---|---|---|
| D1 Clarity & explicitness | Met | 'it' resolves to the flag work via session context |
| D2 Specificity & constraints | - | no new constraint is introduced this turn |
| D3 Output format & length | - | n/a |
| D4 Context & motivation | - | n/a |
| D5 Grounding / reference | - | n/a |
| D6 Examples (show-not-tell) | - | n/a |
| D7 Positive framing | - | n/a |
| D8 Uncertainty handling | - | n/a |
| D9 Decomposition fit | Met | single step |
| D10 Structural economy | Met | appropriately terse in form, though vague in content |
| E1 Success is defined | Missing | 'work' states no pass condition of its own, and doesn't confirm the prior acceptance line still applies |
| E2 Criteria are measurable | Partial | measurable only if 'work' maps onto the earlier acceptance criteria, which is never stated |
| E3 Multidimensional coverage | - | n/a |
| E4 Failure modes anticipated | - | n/a |

**Transformation - turn each gap into a rewrite**

| Rubric | You wrote | Best-practice rewrite | Principle |
|---|---|---|---|
| E1 | make it work | implement the --dry-run flag now so it passes the acceptance criteria above | A vague success word doesn't inherit a definition from a prior turn automatically — say explicitly that the earlier acceptance criteria still apply. |

- **Full rewritten prompt:** _implement the --dry-run flag now so it passes the acceptance criteria above_

### Floating referent, no message or scope - band: bad, score 65 (WEAK)
> commit this

_Source: `SAMPLE — generic example prompts, not real data` &middot; 2026-08-11 &middot; chain_step_

- **Why it lands here:** Names the right verb (commit) but 'this' has no prior turn to resolve against, and no message or scope is given.

**Rubric scorecard**

| Rubric dimension | Status | Why (evidence) |
|---|---|---|
| D1 Clarity & explicitness | Partial | 'this' is the first turn in the session — nothing resolves it |
| D2 Specificity & constraints | Partial | no commit message or file scope given |
| D3 Output format & length | - | n/a |
| D4 Context & motivation | - | n/a |
| D5 Grounding / reference | - | n/a |
| D6 Examples (show-not-tell) | - | n/a |
| D7 Positive framing | Met | phrased as what to do |
| D8 Uncertainty handling | - | n/a |
| D9 Decomposition fit | Met | single step |
| D10 Structural economy | Met | brief, not over-engineered |
| E1 Success is defined | Partial | a commit existing is clear, but correctness of its message/scope isn't measurable without more |
| E2 Criteria are measurable | Partial | partially measurable (did a commit happen) but not fully (is it the right one) |
| E3 Multidimensional coverage | - | n/a |
| E4 Failure modes anticipated | - | n/a |

**Transformation - turn each gap into a rewrite**

| Rubric | You wrote | Best-practice rewrite | Principle |
|---|---|---|---|
| D1 | commit this | commit the deploy.sh change with a message describing the --dry-run flag | Name what 'this' refers to and give a message — don't leave the target of a destructive-adjacent git op implicit. |

- **Full rewritten prompt:** _commit the deploy.sh change with a message describing the --dry-run flag_

### Category word instead of the actual command - band: bad, score 56 (WEAK)
> version-control it to the shared repo

_Source: `SAMPLE — generic example prompts, not real data` &middot; 2026-08-11 &middot; chain_step_

- **Why it lands here:** 'version-control' names a category of git operations, not one of them — commit, push, and opening a PR are all consistent with the wording.
- **Chain step:** Follows 'commit this' in the same session.

**Rubric scorecard**

| Rubric dimension | Status | Why (evidence) |
|---|---|---|
| D1 Clarity & explicitness | Partial | 'version-control' names a category, not a specific git operation |
| D2 Specificity & constraints | Partial | 'to the shared repo' names a target but not which remote/branch |
| D3 Output format & length | - | no meaningful output format beyond the git operation itself |
| D4 Context & motivation | - | motivation wouldn't change which git command applies |
| D5 Grounding / reference | - | no factual grounding needed |
| D6 Examples (show-not-tell) | - | no example needed for a one-line directive |
| D7 Positive framing | Met | phrased as what to do, not what to avoid |
| D8 Uncertainty handling | - | not a factual-risk task |
| D9 Decomposition fit | Met | a single step, not artificially split |
| D10 Structural economy | Met | brief, not over-engineered |
| E1 Success is defined | Missing | no notion of 'done' — a commit-only, a push, and an opened PR are all consistent with the wording |
| E2 Criteria are measurable | Partial | can't binary-check 'version-controlled' without knowing which git action was meant |
| E3 Multidimensional coverage | - | a single quality axis is at stake here |
| E4 Failure modes anticipated | - | no new failure mode beyond the verb ambiguity already scored |

**Transformation - turn each gap into a rewrite**

| Rubric | You wrote | Best-practice rewrite | Principle |
|---|---|---|---|
| D1 | version-control it | commit the deploy.sh change with a message describing the --dry-run flag, then push it to origin/main | Name the actual git command (commit / push / open a PR) — a category word forces the model to guess which one you meant. |

- **Full rewritten prompt:** _commit the deploy.sh change with a message describing the --dry-run flag, then push it to origin/main_

## Habits to build
- Replace a vague success word ('work', 'version-control', 'handle it') with the exact action or an explicit acceptance line.
- On the first turn of a git-adjacent ask, name the file/scope and give a message — don't leave a 'this' with nothing to resolve against.
- When a follow-up turn relies on an earlier acceptance line, say so explicitly rather than assuming the model will re-apply it.

## Habits you already have
- Appropriately terse chain steps ('now push it', 'ok continue') when the referent genuinely resolves from context — brevity isn't being overused to hide ambiguity.
- When a task is spelled out (the --dry-run flag prompt), it's spelled out completely: scope, format, and a binary acceptance line together.
