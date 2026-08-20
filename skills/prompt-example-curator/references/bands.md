# Prompt Bands & Example Selection

## Mapping a prompt-critic result to a band

Use the critic's `overall.verdict` first, then `overall.score` as the tie-breaker. A
`blocking` gap always lands in `bad`, regardless of score.

| Band | Critic verdict | Score guide | Meaning |
|---|---|---|---|
| **excellent** | `STRONG` | ≥ 85, no blocking gaps | Imitate this. Clear intent, right amount of structure, success is definable. |
| **good** | `ADEQUATE` | 70–84 | Works, but one or two high-leverage fixes would make it excellent. |
| **bad** | `WEAK`, `POOR`, or `BLOCKED` | < 70, or any blocking gap | Anti-pattern. Must be shown with a rewrite. |

Chain steps are banded the same way — a short follow-up turn that the session fully
resolves and that advances a clearly-defined task can be `excellent`; a terse turn whose
referent or verb is genuinely ambiguous is `bad`.

## Selecting examples for the guide

Pick the **most instructive real prompts**, not the highest/lowest scores mechanically.

- **Excellent (2–4 examples):** clean exemplars that show a specific strength — stated
  acceptance criteria, an unambiguous action verb, the right economy for a follow-up turn.
  For each, name the dimension(s) that make it strong so the user can reproduce the habit.
- **Good (2–3 examples):** "almost there" prompts. Show the prompt, the single fix that
  would lift it to excellent, and the refined version. These teach the fastest.
- **Bad (2–4 examples):** distinct failure modes — floating reference, undefined verb,
  untestable success word, over-engineering. Each MUST be paired with the critic's
  `refined_prompt` as a before→after. Avoid stacking multiple examples of the same failure.

Selection rules:
- **Diversity over redundancy** — one example per failure/strength mode; retire an old
  example when a sharper one for the same lesson arrives.
- **Real and attributed** — verbatim prompt text, source log/branch, and date on every one.
- **Chain-step honesty** — label follow-up turns; when brevity is correct, say so, so the
  guide never teaches "add more words" as a blanket rule.
