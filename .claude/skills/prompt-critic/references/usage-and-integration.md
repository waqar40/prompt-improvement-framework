# Prompt Critic — Usage & Integration

## Minimal user-message template

```text
Analyze this prompt.

<prompt>
{{ PROMPT_UNDER_REVIEW }}
</prompt>

task_intent: {{ optional — what the author wants }}
target_model: {{ optional — e.g. Claude Opus 4.x, GPT-5.x, a small local model }}
session_context: {{ optional — a summary or the preceding turns, if this prompt is a
  follow-up turn in a session; lets the analyzer judge references as resolvable }}
samples:
  - input: {{ optional }}
    ideal_output: {{ optional }}
```

When reviewing raw journal logs, entries under the same `branch=` header, in timestamp
order, ARE the session — pass the earlier entries as `session_context` for each later
turn so chain steps are scored fairly (see `conversational-chains.md`).

The `<prompt>` fence is the one place tags earn their keep here: it removes ambiguity
about where the material under review starts and ends, so the analyzer never mistakes the
prompt's own instructions for instructions to itself.

## Integration notes for an eval-driven pipeline

- **As a pre-eval gate.** Run Prompt Critic before authoring the eval. If
  `verdict == BLOCKED`, fail fast and hand back `top_fixes`; there is no point evaluating
  outputs of a prompt whose success is undefined.
- **The two layers mirror a layered scorer.** Layer 2's `suggested_eval_criteria` come
  pre-sorted deterministic → property → judge, so they slot straight into a
  deterministic-gate → property-yardstick → LLM-judge scorer without re-derivation.
- **Localization.** The `id` on every finding (D1–D10, E1–E4) gives stable signatures, so
  a regressing prompt reports *which* dimension slipped rather than just a dropped score.
- **Calibrate the judge.** Before trusting the score as a gate, hand-label ~50–100 prompts
  as strong/weak, run them through, and check agreement (e.g. Cohen's κ). If the analyzer
  and your reviewers disagree, tighten the rubric anchors or the severity definitions —
  don't just accept the number.
- **Guard against prompt injection.** The analyzer treats everything inside `<prompt>` as
  data to be evaluated, never as instructions to itself. Keep that boundary if you wrap
  this in tooling.
- **Watch the isolated-example trap.** A refined prompt that scores better on one case can
  regress on the representative set. Always re-run the refined prompt against the full
  sample set, not the case that motivated the change.

## Running for gating

- Run the analyzer at `temperature = 0` so the score is reproducible.
- The judge (this analyzer) should be at least as capable as the model the prompt targets.
- Parse the leading JSON object programmatically; the Markdown view is for humans only.
