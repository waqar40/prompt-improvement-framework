# Prompt Critic — Rubric, Scoring, and Verdicts

Score each dimension **only if it is APPLICABLE** to the task. For each dimension assign
a verdict:

- `met` — present and adequate
- `partial` — present but weak, vague, or incomplete
- `gap` — needed by the task but absent
- `na` — not needed by this task (does not affect score)

Assign a `severity` to every `partial` and `gap`:

- `blocking` — the prompt cannot reliably produce acceptable output until fixed
- `major` — materially degrades reliability, quality, or consistency
- `minor` — polish; worth fixing but not load-bearing

`met` and `na` dimensions carry severity `none`.

## Layer 1 — Design (does the prompt contain what drives good behavior?)

| id  | dimension                 | what "met" looks like                                                                              | weight |
|-----|---------------------------|-----------------------------------------------------------------------------------------------------|--------|
| D1  | Clarity & explicitness    | A single unambiguous instruction led by an action verb; no contradictory directives                | 3      |
| D2  | Specificity & constraints | Audience, scope, boundaries, and any hard limits (length, budget, restrictions) stated              | 3      |
| D3  | Output format & length    | Desired structure/format and length specified or clearly implied                                    | 2      |
| D4  | Context & motivation      | The *why* / purpose / how the output is used, where that would change the answer                    | 2      |
| D5  | Grounding / reference     | Reference text or source-of-truth provided where factual accuracy matters                           | 2      |
| D6  | Examples (show-not-tell)  | 1–few aligned examples where format/tone is easier shown than described                             | 2      |
| D7  | Positive framing          | Instructions say what TO do rather than only what NOT to do                                         | 1      |
| D8  | Uncertainty handling      | Explicit permission to say "I don't know" / flag insufficient info, where hallucination risk exists | 1      |
| D9  | Decomposition fit         | Task is either simple enough for one prompt, or correctly broken into steps                         | 2      |
| D10 | Structural economy        | Minimum necessary scaffolding; no over-engineering, no technique-stacking, no dead instructions     | 2      |

Calibration notes:
- D5 is `na` for purely creative or opinion tasks with no ground truth.
- D6 is `na` when instructions alone reliably convey format; do not demand examples reflexively.
- D8 is `na` for tasks with no factual risk (e.g. brainstorming).
- For modern frontier target models, heavy role prompting and decorative XML are NOT
  merits — count them under D10 as economy problems if they add nothing.

## Layer 2 — Evaluability (can success be measured?)

| id  | dimension                  | what "met" looks like                                                                       | weight |
|-----|----------------------------|----------------------------------------------------------------------------------------------|--------|
| E1  | Success is defined         | It is clear what a correct/strong output is vs. a weak one                                   | 3      |
| E2  | Criteria are measurable    | Success decomposes into binary checks and/or scalar scales, not vibes                        | 3      |
| E3  | Multidimensional coverage  | Where the task has several quality axes (accuracy, format, tone, safety), all are covered    | 2      |
| E4  | Failure modes anticipated  | Likely failure modes (verbosity, fabrication, off-topic, format drift) are guarded against   | 2      |

If success is genuinely undefinable from the prompt AND cannot be inferred, E1 is a
`blocking` gap.

**Using `assets_used` context (if supplied).** When the journal entry carries an
`assets-used` block (which skills/subagents/tools actually ran as a result of the prompt),
treat it as *corroborating evidence*, never as an automatic penalty:
- A prompt whose stated intent implies a change (`"fix"`, `"add"`, `"refactor"`) but whose
  `assets_used` shows only read-only tools (`Read`, `Grep`) and no `Edit`/`Write` is
  evidence the prompt may have left success genuinely ambiguous (E1/E2) — cite the mismatch
  as evidence for a gap you'd otherwise have to infer blind, but only if the prompt text
  itself doesn't already make the ambiguity clear some other way.
- Tools/skills invoked that have nothing to do with the stated task can be evidence of a
  D1/D2 clarity or scope gap (the agent had to guess).
- **Never penalize the prompt for how the agent executed it.** A well-specified prompt can
  legitimately result in no edits (e.g. "check whether X is already handled" — the correct
  answer might be "yes, no change needed"). Use `assets_used` to sharpen evidence for a gap
  the rubric would flag anyway — never as a new, separate scored dimension.

## Scoring

1. Sum `weight` over all APPLICABLE dimensions → `weight_total`.
2. Award points per dimension: `met` = full weight, `partial` = half weight, `gap` = 0.
3. `score = round(100 * awarded / weight_total)`.
4. Determine `verdict`:
   - Any `blocking` gap present → `BLOCKED` (regardless of score).
   - Else score ≥ 85 → `STRONG`
   - Else score 70–84 → `ADEQUATE`
   - Else score 50–69 → `WEAK`
   - Else → `POOR`

`BLOCKED` means: do not ship as-is; the refined prompt must resolve every blocking gap.
