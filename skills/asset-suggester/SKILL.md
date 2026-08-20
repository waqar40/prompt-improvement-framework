---
name: asset-suggester
description: Use after prompts have been scored (by prompt-critic, via the prompt-journal pipeline) to detect recurring work that should become a reusable Claude Code asset — a skill, subagent, hook, slash command, rule, or script — and record deduped candidates in suggestions/<user>.json. Reads the score store plus any per-prompt asset_hints, clusters repeated intents/tools/tasks, types each candidate, and proposes where it should live. Triggers include "suggest assets", "what could be a skill", "find reusable patterns in my prompts", "refresh asset suggestions", and Step 5 of the prompt-journal pipeline. Does not author assets — asset-architect does that.
---

# Asset Suggester

Turn a scored prompt journal into a list of **reusable-asset candidates**. You spot what the
user does **repeatedly** or **imperatively**, decide the likely asset *type*, and record it —
you do **not** build the asset (that is `asset-architect`) and you do **not** re-score prompts
(that is `prompt-critic`). Recurrence is the core signal a single prompt review cannot see;
your job is to see across the whole journal.

**Paths** — the score store and suggestions live under the **outcomes dir** `<outcomes>`
(`PROMPT_OUTCOMES_DIR`, default `~/.claude/prompt-journal/prompts-review-outcomes`), NOT inside the repo:
read `<outcomes>/scores/<user>.jsonl`, write `<outcomes>/suggestions/<user>.json`.

## References — read before clustering

| File | Contents |
|---|---|
| `references/clustering.md` | How to cluster prompts into candidates, the recurrence threshold, and the signal → asset-type map (the authoritative decision matrix lives in `asset-architect`). |
| `references/suggestion-schema.md` | The exact `suggestions/<user>.json` schema and merge/idempotency rules. |

## Inputs

- `results` (optional): this run's prompt-critic results, each with its prompt, source,
  `project`, `root`, `branch`, date, `top_dimensions`, `assets_used`, and any `asset_hint`.
- `user` (required): whose store/suggestions to update (e.g. `waqar.aziz`).
- `store` (optional): `scores/<user>.jsonl` — the full history (now carries `project`/`root` and
  `assets_used` per row); read it so recurrence is measured across the whole journal, not just
  this run.

## Workflow

### Step 1 — Gather signals
Read `scores/<user>.jsonl` (and this run's `results`). For each entry keep: the prompt
excerpt, source/branch, **project + root**, date, the intent (what the user asked for), the
tools/verbs involved, and any `asset_hint`. **Prefer `assets_used` (what actually ran) over
verbs inferred from the prompt text when both are available** — it's stronger evidence: a
skill/subagent already invoked repeatedly for the same recurring need means that need may
already be well-served (weigh it down as a candidate, or note it as "already covered by
`<name>`"); the same manual sequence of file edits with no skill/subagent, repeated across
entries, is stronger recurrence evidence than text alone. Fall back to inferring verbs from the
prompt text when `assets_used` is empty (most rows, still — this predates the feature and
covers turns with no trackable tool use). An `asset_hint` is a *shape* flag, not proof of recurrence.

### Step 2 — Cluster into candidate needs
Group entries by shared intent / tool / task per `references/clustering.md` (normalize verbs
and referents so "commit + push", "version-control it", "push it" cluster together). A
cluster is a candidate when it meets the recurrence threshold **or** carries a strong
single-shot `asset_hint` (e.g. a "whenever X" guarantee → hook).

### Step 3 — Type, locate, and ground each candidate
Assign the likely asset `type` (skill / agent / hook / command / rule / script) using the
signal → type map in `references/clustering.md`. Propose a `target_location` and, for
skills/commands, a `proposed_trigger`. Then fill the **machine-readable metadata** so
`asset-architect` can trace the real repo (see `references/suggestion-schema.md`):
`target_project{name, root_path, git_remote, branches}` from the evidence's `project`/`root`
headers (primary = most frequent project; never guess a path when the header is absent), and
`grounding{claude_md, rules_dir, code_globs}` as best-effort pointers under `root_path`. Set
`confidence` from cluster strength + evidence count. Keep the type provisional — `asset-architect`
makes the authoritative call.

### Step 4 — Merge into the suggestions file
Write `suggestions/<user>.json` per `references/suggestion-schema.md`. **Merge, do not
clobber**: update `frequency`/`evidence` on an existing candidate, add new ones, and never
overwrite a candidate a human has edited or whose `status` is past `proposed`
(`accepted`/`authored`/`dismissed`). Idempotent — re-running adds no duplicates.

### Step 5 — Report
List new + updated candidates with their type, frequency, and one-line rationale, and point
the user at `/scaffold-asset` to author any of them.

## Constraints

- NEVER author, scaffold, or write the asset itself — only propose it; `asset-architect` builds it.
- NEVER re-score prompts or edit the raw logs / the score store history.
- NEVER fabricate evidence — every candidate cites real prompt excerpts with source + date.
- ALWAYS measure recurrence across the whole store, not just the current run.
- ALWAYS keep the file idempotent and merge-safe; never downgrade or overwrite a non-`proposed` candidate.
- Keep types provisional and defer the final type/placement decision to `asset-architect`.
