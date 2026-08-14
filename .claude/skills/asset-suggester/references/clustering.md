# Clustering prompts into asset candidates

## Normalize before grouping

Reduce each prompt to an **intent signature** so surface-different prompts that mean the same
thing cluster together:
- Canonicalize the **verb/action** (commit, push, open-PR → `version-control`; "try X", "run
  X", "check X" → `invoke/verify`).
- Strip **floating referents** (`it`, `this`, `the PR`) and volatile tokens (SHAs, ticket ids,
  paths) to their *kind*.
- Keep the **tool/target** (jira, bitbucket, git, a script name, a switch/vendor).

Group by `(canonical action + target)`. Two prompts in the same group are one recurrence.

## Recurrence threshold

- **≥ 3 occurrences** of the same intent signature → strong candidate (Anthropic's "third
  manual repetition" mark).
- **2 occurrences** → weak candidate; record with `confidence: "low"` and let it strengthen on
  the next run.
- **1 occurrence** → a candidate **only** if it carries a strong `asset_hint` whose signal is
  inherently non-recurrence-based (a "whenever X, do Y" guarantee, or a fragile deterministic
  step) — see the type map below.

`frequency` = occurrence count across the whole store.

## Signal → asset-type map (provisional)

Repetition tells you to *capture* the need; the **signal** tells you *what type*. (The
authoritative decision matrix lives in `asset-architect/references/decision-matrix.md`; use
this lighter version to type a candidate.)

| Signal in the clustered prompts | Provisional type |
|---|---|
| A repeated **multi-step procedure / playbook** you re-explain | `skill` |
| A repeated **reference lookup** or knowledge you keep restating | `skill` |
| A durable **fact / convention / NEVER-ALWAYS rule** you keep correcting | `rule` (or CLAUDE.md) |
| A "**whenever X, do/deny Y**" guarantee that must hold every time | `hook` |
| A repeated **isolated, multi-step delegated task** (own context/tools) | `agent` |
| A **prompt you keep typing to start a task** | `command` |
| A **fragile, deterministic** operation better done by exact code | `script` |

Notes:
- Prefer `rule`/CLAUDE.md over `skill` for a *fact*; prefer `skill` over `rule` for a
  *procedure*; prefer `hook` over both when the requirement is a guarantee (memory/skills
  only *steer*; hooks *enforce*).
- When two types fit, record the higher-leverage one and note the alternative in `rationale`.

## Confidence

- `high` — ≥ 3 occurrences across ≥ 2 sources/dates, consistent intent.
- `medium` — ≥ 3 occurrences in one source, or 2 occurrences + a matching `asset_hint`.
- `low` — 2 occurrences, or a single strong `asset_hint`.
