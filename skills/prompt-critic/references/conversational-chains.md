# Prompt Critic — Scoring Conversational Chains & Short Prompts

Most real prompts in this journal are **turns inside a running session**, not standalone
prompts. They are short and deliberately lean on context the session already holds:
`"yes clean it up"`, `"push it"`, `"open a PR"`, `"are we good to merge?"`. Scoring these
as if they were one-shot prompts would be wrong — it would flag every follow-up as
"floating reference" or "missing context" when the context genuinely existed a turn
earlier. This file defines how to judge them fairly.

## Core principle

Judge a chain step against **what is resolvable from the established session**, not
against the ideal of a self-contained prompt. A short prompt is not a weak prompt. Length
is never itself a fault — a one-word `"yes"` can be a perfectly good confirmation turn.

## When the prompt is a `chain_step`

Set `prompt_kind = "chain_step"`. Then:

- **Resolvable references are `met`/`na`, not gaps.** If `it`, `the PR`, `that file`, or a
  missing constraint would be unambiguously resolved by the immediately-preceding turns,
  do NOT record D1 (clarity) or D4/D5 (context/grounding) as a gap. Note in `evidence`
  that the referent is carried by session context.
- **Brevity is not penalized.** Do not raise D2/D3 (specificity/format) gaps solely
  because the turn is terse; a follow-up inherits the standing task and format.
- **Evaluability is inherited.** E1/E2 can be `met` when the success condition was set by
  an earlier turn (e.g. an acceptance-criteria prompt) and this turn just advances it.

## What still counts against a chain step

A follow-up turn is NOT automatically excellent. Flag a gap only when the weakness is
**real given the session**, i.e. the context does *not* resolve it:

- **Genuinely ambiguous referent** — a pronoun with two or more plausible antecedents in
  the recent turns (the model would have to guess). This is a real D1 gap.
- **Undefined verb the session never pinned down** — `"version-control it"` when no prior
  turn specified commit vs. push vs. PR. Real D1/D2 gap even mid-session.
- **Untestable success word** — `"make it work seamlessly"` with no pass condition stated
  now or earlier. Real E1/E2 gap.
- **A new sub-task introduced in this turn** that carries its own unmet requirements —
  score those normally.

## Inputs that help

If `session_context` is supplied (a summary or the preceding turns), use it to decide
resolvability. If it is **absent**, do not assume favorable context: state in
`assumptions` that you are treating the turn as best-effort standalone, resolve what the
prompt text plainly implies, and reserve `blocking` severity for cases where intent is
truly unrecoverable. Prefer `major`/`minor` over `blocking` for a chain step whose only
sin is relying on context you cannot see.

## Refining a chain step

The refined prompt for a chain step should stay a **natural next turn** — tighten the one
ambiguous referent or undefined verb, keep it short. Do NOT rewrite it into a bloated
self-contained prompt that repeats everything the session already knows; that would
violate structural economy (D10). If the turn is fine as-is given context, say so and
return it unchanged with an empty `changelog`.
