---
name: catalog
description: Use to print the prompt-journal framework's capability guide — a catalog of every command, skill, and agent in this repo with its usage, inputs, and outcomes. Triggers include "help", "list commands", "list skills", "what can this repo do", "what commands are available", "show me the skills", and the /catalog command.
---

# Prompt Journal — capability guide

Print a catalog of everything in this repo. First **reconcile with disk**, then render the
tables so the guide never drifts.

## Workflow

### Step 1 — Reconcile with what's installed
List `${CLAUDE_PLUGIN_ROOT}/commands/*.md`, `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md`, and
`${CLAUDE_PLUGIN_ROOT}/agents/*.md` (the agents dir may not exist — that's fine). Compare against
the tables below. If anything is on disk but missing from the tables, add a row from its
front-matter `description`; if a table row no longer exists on disk, drop it. Note any
reconciliation you had to do.

### Step 2 — Render the catalog
Print the sections below (Pipeline, Commands, Skills, Agents), then the one-line "typical
flow". Keep tables intact; render as Markdown.

---

## The pipeline at a glance

Data lives OUTSIDE the plugin: INPUT in the journal dir (default `~/.claude/prompt-journal/prompts`),
OUTPUT in the outcomes dir (default `~/.claude/prompt-journal/prompts-review-outcomes`). The
plugin itself is machinery only.
```
prompt ──▶ [record-prompt hook] ──▶ <journal>/<branch>.txt                (raw log; header: branch+project+root)
       ──▶ [PostToolUse + Stop hooks] ──▶ appends "assets-used" block to that entry (skills/subagents/tools + paths)
       ──▶ /analyse (ALL logs by default) ──▶ prompt-critic ──▶ <outcomes>/scores/<user>.jsonl   (score each turn,
                                                                  assets-used as context, never a score input)
                     ──▶ per-file review ──▶ <outcomes>/reviews/<user>/<branch>.md   (session strengths/weaknesses + asset ideas)
                     ──▶ progress-coach ──▶ <outcomes>/progress/<user>.*   (adaptive focus + pace, deterministic math)
                     ──▶ prompt-example-curator ──▶ <outcomes>/guides/<user>.*  (OVERALL guide, embeds the focus teaser)
                     ──▶ asset-suggester ──▶ <outcomes>/suggestions/<user>.json (machine-readable: target_project + grounding)
       ──▶ /scaffold-asset ──▶ asset-architect ──▶ traces the real repo ──▶ a new skill/agent/hook/command/rule/script
       ──▶ /review-asset ──▶ artifact-reviewer (read-only) ──▶ findings tagged mechanical|needs-authoring
                     ──▶ /fix-asset ──▶ asset-fixer (mechanical only)     ──▶ /scaffold-asset (needs-authoring)
```
(`<journal>` = `PROMPT_JOURNAL_DIR`, default `~/.claude/prompt-journal/prompts`. `<outcomes>` =
`PROMPT_OUTCOMES_DIR`, default `~/.claude/prompt-journal/prompts-review-outcomes`.)

## Commands (`/name`)

| Command | Usage | Input | Outcome |
|---|---|---|---|
| `/configure` | `/configure [--legacy-hook] [--journal <path>]` | OS + optional flags | Ensures the journal/outcomes dirs exist, self-tests the recorder, installs optional PDF/Word deps. The `UserPromptSubmit` hook itself is wired automatically by the plugin's `hooks/hooks.json` — pass `--legacy-hook` only when running this repo standalone (not as an installed plugin). |
| `/analyse` | `/analyse [<file-or-dir> \| --project <name> \| --branch <name>] [--user <name>]` | **Default: the whole journal** (`~/.claude/prompt-journal/prompts`); or narrow to a file/dir, project, or branch | Runs the whole pipeline (all outputs under the outcomes dir): scores every prompt, writes a per-file review to `reviews/<user>/<branch>.md`, appends to `scores/<user>.jsonl`, updates the adaptive `progress/<user>.*` (current focus + pace), compiles the **overall** `guides/<user>.*` from the full store (embedding the focus), and updates machine-readable `suggestions/<user>.json`. Idempotent. |
| `/prompt-review` | `/prompt-review [<file-or-dir> \| --project <name> \| --branch <name>] [--user <name>]` | Same as `/analyse` | Back-compat alias of `/analyse` — identical behaviour. |
| `/review-asset` | `/review-asset [<asset-file-or-dir>] [--focus <type\|rubric>]` | An asset file, an asset dir, or a repo (default: the current repo's `.claude/` or plugin-root `commands/`/`skills/`/`agents/`, whichever exists) | **Read-only audit** of existing skills/agents/hooks/commands/rules/scripts against the shared quality gate (frontmatter + anatomy + 7 rubrics + instructional semantics [contradiction/ambiguity/persona/cognitive-load/coverage/composition-conflict] + non-destructive permissions + model tier + verification). Runs `validate-frontmatter.py`, then judgment review; returns findings + score + **PASS/FAIL**, each finding tagged mechanical vs. needs-authoring. Never edits — mechanical fixes route to `/fix-asset`, everything else to `/scaffold-asset`. |
| `/fix-asset` | `/fix-asset <asset-file> [--findings <path-or-json>]` | An asset file + an `artifact-reviewer` findings report (runs `/review-asset` first if omitted) | Applies **only** the findings labeled mechanical (dangling reference, invalid frontmatter key, stale table row) verbatim — never authors new content. Skips and reports anything needing judgment. |
| `/scaffold-asset` | `/scaffold-asset <suggestion-id \| inline need> [--repo <path>] [--confluence <url\|id>] [--docs <path>] [--code <glob>] [--prompts <log>] [--user <name>]` | A `suggestions/<user>.json` id (carrying `target_project` + `grounding`) or an inline need, plus optional grounding sources | Builds a **grounding brief** from repo code + CLAUDE.md/rules + Confluence pages + docs + raw prompts, then emits the right asset **type + placement** to the artifact anatomy **with a verification** — **only after you approve the draft**. |
| `/catalog` | `/catalog` | — | Prints this capability guide (commands, skills, agents with usage/input/outcome). |
| `/test` | `/test` | — | End-to-end tests the framework: runs `scripts/selftest.sh`, then drives every key skill/command over fixtures in an isolated `_selftest` sandbox and reports PASS/FAIL. Touches no real data. |

## Skills (auto-trigger on phrases, or invoked by a command)

| Skill | Usage / triggers | Input | Outcome |
|---|---|---|---|
| `prompt-critic` | "review/score/rate/critique this prompt" | One prompt (user or system), optional `session_context` of earlier turns, optional `assets_used` (skills/subagents/tools that actually ran) | A machine-parseable **JSON contract** (score, verdict, `suggested_eval_criteria`, localized gaps, `execution_context`) + a short Markdown summary and a rewrite. `assets_used` is context only — never a scored dimension. The scoring source of truth. |
| `prompt-example-curator` | "curate examples", "update my guide", "band these prompts" | prompt-critic output (or the score store) for a user, + `progress-coach`'s focus teaser | Bands each prompt **bad / good / excellent**, picks the most instructive real examples, embeds the current focus, and writes them (verbatim, with before→after rewrites) into `guides/<user>.md`. |
| `progress-coach` | "why am I not improving", "what should I focus on next" (a step inside `/analyse`, not user-invoked directly) | The score store's per-dimension `dims` history + the prior `progress/<user>.json` | Deterministic EWMA/pace/mastery math (`scripts/compute-progress.py`) picks **one** next-focus dimension, flags regressions on previously-mastered ones, and writes `progress/<user>.{json,md}` with concrete steps from `references/dimension-playbooks.md`. See `docs/adr/0001-adaptive-personalized-progress-coaching.md`. |
| `asset-suggester` | "suggest assets", "what could be a skill", "find reusable patterns" | The score store (+ `project`/`root`) + each prompt's optional `asset_hint` | Clusters recurring intents/tools/tasks into deduped, **machine-readable** candidates in `suggestions/<user>.json` — each with `target_project{name,root_path,git_remote,branches}` + `grounding{claude_md,rules_dir,code_globs}`. Proposes only — never builds. |
| `asset-architect` | "turn this into a skill", "should this be a hook or a rule", "scaffold an asset", "generate an artifact grounded in this confluence page / doc / code" | A suggestions candidate (or inline need); target repo defaults to the candidate's `root_path` | A **multi-source grounding consumer**: builds a grounding brief from repo code + CLAUDE.md/rules + Confluence + docs + raw prompts, picks asset **type + placement**, emits it to the **artifact anatomy** — addressing the 7 rubrics (correctness/latency/cost/security/observability/scale/reliability), non-destructive permissions, and a model tier — **with a verification**, then scaffolds **after approval**. |
| `prompt-journal` | "run the prompt pipeline", "analyse all my prompts" (the engine behind `/analyse`) | **Default: the whole journal** (`~/.claude/prompt-journal/prompts`), or a file/`--project`/`--branch` + a user | Orchestrates score → per-file review → store → **adaptive progress** → **overall** guide → machine-readable suggestions, treating entries under one `branch=` header as one session/chain. |
| `configure` | "configure", "set up the hook", "fix my prompt journal hook" (the engine behind `/configure`) | OS + optional `--journal` / `--legacy-hook` | Detects OS, runs `scripts/configure.*`, ensures the journal/outcomes dirs exist, self-tests the recorder, and reports `[OK]`/`[FIXED]`/`[ACTION]`. |
| `artifact-reviewer` | "review this skill/agent/hook", "audit my .claude assets", "does this follow best practices" (engine behind `/review-asset`) | an asset / dir / repo (default: current repo root) | Read-only audit against the shared **quality gate** (frontmatter + anatomy + 7 rubrics + instructional semantics [Section G: contradiction/ambiguity/persona/cognitive-load/coverage/composition-conflict] + permissions + model + verification); scored findings + PASS/FAIL, each tagged mechanical vs. needs-authoring; routes mechanical fixes to `asset-fixer`, the rest to `asset-architect`. |
| `asset-fixer` | "fix this skill", "apply the review findings" (engine behind `/fix-asset`) | an asset file + an `artifact-reviewer` findings report | Applies only the **mechanical, fully-specified** fixes verbatim (dangling reference, invalid frontmatter key, stale table row); never authors content — skips + reports anything needing judgment. |
| `catalog` | "help", "list commands/skills" (the engine behind `/catalog`) | — | Renders this catalog. |
| `test-framework` | "test the framework", "self-test", "verify the pipeline" (the engine behind `/test`) | fixtures under `tests/fixtures/` | Runs the harness + drives every skill/command in a `_selftest` sandbox, checks outcomes, tears down, reports PASS/FAIL. |

## Agents (subagents)

This repo defines **no repo-local subagents** (`agents/` is absent). The pipeline runs through
the skills above. Asset candidates that should become a subagent are proposed by
`asset-suggester` and scaffolded by `asset-architect`/`/scaffold-asset` — into the target
repo, not necessarily here.

## Typical flow

Install the plugin once (recorder hook is active immediately) → work normally (prompts
auto-record to `~/.claude/prompt-journal/prompts`) → `/analyse --user <you>` at end of day →
read `~/.claude/prompt-journal/prompts-review-outcomes/guides/<you>.md` (its "Your Focus Right
Now" points at the fuller `progress/<you>.md`) → optionally `/scaffold-asset` a recurring pattern.

## Non-command scripts (for reference)

| Script | Purpose |
|---|---|
| `scripts/record-prompt.{ps1,sh}` | The recorder hook itself — appends each prompt to `<journal>/<branch>.txt`. Wired automatically by `hooks/hooks.json`; not run by hand. |
| `scripts/record-tool-use.{ps1,sh}` | `PostToolUse` hook — buffers Skill/Task/file-tool invocations for the current turn. Wired automatically; not run by hand. |
| `scripts/record-turn-end.{ps1,sh}` | `Stop` hook — flushes the buffer into an `assets-used` block on that turn's journal entry. Wired automatically; not run by hand. |
| `scripts/configure.{ps1,sh}` | Creates the journal/outcomes dirs, self-tests the recorder, installs optional deps; invoked by `/configure`. |
| `scripts/render-guide.py` | Renders `guides/<user>.json` to Markdown + PDF + Word (incl. the "Your Focus Right Now" section, when `focus_plan` is present). |
| `scripts/compute-progress.py` | Deterministic EWMA/pace/mastery engine behind `progress-coach` — no LLM call, unit-tested by `selftest.sh`. |
| `scripts/selftest.sh` | Deterministic sandboxed self-test of the scripts + schemas; first step of `/test`. |
| `scripts/validate-frontmatter.py` | Deterministic frontmatter gate for skills/commands/agents; first step of `/review-asset` (wireable as a hook/CI gate). |
