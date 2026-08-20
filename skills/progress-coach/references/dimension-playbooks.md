# Dimension Playbooks — concrete steps & rules per rubric dimension

One reusable, hand-written playbook per D1–D10/E1–E4 (mirrors `prompt-critic/references/rubric.md`'s
dimension list). `progress-coach` picks 1–2 items from the **current focus dimension's** entry and
adapts them to the user's own recent evidence — it does not improvise generic advice from scratch,
and it does not dump the whole playbook; one concrete rule + one exercise per run is the point.

## D1 — Clarity & explicitness
- **Rule:** Open with one action verb naming the deliverable ("Add", "Fix", "Rewrite", "Explain") —
  never a bare noun phrase or a question when you actually want an action taken.
- **Rule:** Replace every `it`/`this`/`that` with the actual noun, unless the immediately
  preceding turn in the same session already named it unambiguously.
- **Exercise:** Read your first sentence alone, out of context. If it could mean two different
  actions, name the one you mean.

## D2 — Specificity & constraints
- **Rule:** Name the file/module/function in scope explicitly ("in `scripts/deploy.sh`", not "in
  the deploy script").
- **Rule:** State hard limits explicitly (length, budget, forbidden approaches) — don't rely on
  Claude to infer a boundary you didn't say.
- **Exercise:** List the boundaries you'd be annoyed to see violated, then check you actually said them.

## D3 — Output format & length
- **Rule:** If you need a specific shape (table, diff, one-liner, JSON), say so explicitly — "as
  a markdown table," not left implicit.
- **Rule:** State the target length when it matters ("one paragraph", "under 50 lines") — silence
  invites the model's own default verbosity.

## D4 — Context & motivation
- **Rule:** Add the *why* only when it would change the answer — a one-clause "so that X" is
  enough; don't over-explain when the task is already unambiguous without it.
- **Exercise:** Ask "if I didn't say why, would the output actually come out different?" If no,
  this dimension doesn't need anything — `n/a` is the correct verdict, not a gap.

## D5 — Grounding / reference
- **Rule:** Paste or point at the actual source of truth (a file, an error message, a URL)
  instead of describing it from memory.
- **Exercise:** Before sending a "fix X" prompt, paste the real failing output/error text, not a
  paraphrase of it.

## D6 — Examples (show-not-tell)
- **Rule:** When format or tone is genuinely easier to show than describe, give ONE aligned
  example — but don't add examples reflexively when the description alone is already enough
  (that trades a D6 gain for a D10 loss).

## D7 — Positive framing
- **Rule:** Prefer "do X" over "don't do Y" — say what the output should look like, not only
  what to avoid.
- **Rule:** If you must forbid something, pair it with the positive alternative in the same sentence.

## D8 — Uncertainty handling
- **Rule:** For any research/factual task, explicitly permit "say so if you don't know" — this
  measurably reduces confidently-wrong answers.
- **Exercise:** Ask "could the model plausibly fabricate an answer here rather than admit it
  doesn't know?" If yes, say the permission explicitly; if the task has no factual risk, `n/a` is correct.

## D9 — Decomposition fit
- **Rule:** If the ask bundles "analyze/decide" with a large "then build it", split into two
  prompts with a checkpoint between them — don't greenlight a big, open-ended build sight-unseen.
- **Exercise:** Count the independent major verbs in your prompt. More than 2–3 ("review... then
  implement... then also refactor...") is a decomposition smell.

## D10 — Structural economy
- **Rule:** Cut role-play, decorative formatting, and repeated instructions that don't change
  behavior — say each thing once.
- **Exercise:** If you removed the single fluffiest sentence, would the prompt still work? If
  yes, cut it before sending.

## E1 — Success is defined
- **Rule:** End substantive prompts with an explicit "Acceptance:" line naming the observable
  condition that means done.
- **Exercise:** Ask "if I got two different outputs, could I say which one is right?" If not, E1
  is genuinely missing — this is usually the single highest-leverage fix available.

## E2 — Criteria are measurable
- **Rule:** Prefer binary/testable phrasing ("exits 0", "matches this shape", "returns this
  status code") over subjective quality words ("clean", "good", "robust").
- **Exercise:** Replace every quality adjective in your draft with the concrete thing you'd
  actually check to confirm it.

## E3 — Multidimensional coverage
- **Rule:** When a task has more than one quality axis (correctness AND format AND tone), name
  all of them — an implicit axis is the one that silently doesn't get checked.

## E4 — Failure modes anticipated
- **Rule:** Name the specific way this could go wrong for THIS task (verbosity, fabrication,
  off-topic, breaking an existing test) and guard against it explicitly — especially on
  higher-stakes asks (destructive ops, published docs, anything another person will read).
