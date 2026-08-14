---
name: catalog
description: Use to print the prompt-journal framework's capability guide — a catalog of every command, skill, and agent in this repo with its usage, inputs, and outcomes. Triggers include "help", "list commands", "list skills", "what can this repo do", "what commands are available", "show me the skills", and the /catalog command.
---

# Prompt Journal — capability guide

Print a catalog of everything in this repo. First **reconcile with disk**, then render the
tables so the guide never drifts.

## Workflow

### Step 1 — Reconcile with what's installed
List `.claude/commands/*.md`, `.claude/skills/*/SKILL.md`, and `.claude/agents/*.md`
(the agents dir may not exist — that's fine). Compare against the tables below. If anything
is on disk but missing from the tables, add a row from its front-matter `description`; if a
table row no longer exists on disk, drop it. Note any reconciliation you had to do.

### Step 2 — Render the catalog
Print the sections below (Pipeline, Commands, Skills, Agents), then the one-line "typical
flow". Keep tables intact; render as Markdown.

---

## The pipeline at a glance

Data lives OUTSIDE the repo: INPUT in `../prompts/` (journal), OUTPUT in `../prompts-review-outcomes/`
(the outcomes dir). The framework repo is machinery only.
```
prompt ──▶ [record-prompt hook] ──▶ ../prompts/<branch>.txt                (raw log; header: branch+project+root)
       ──▶ /analyse (ALL logs by default) ──▶ prompt-critic ──▶ <outcomes>/scores/<user>.jsonl   (score each turn)
                     ──▶ per-file review ──▶ <outcomes>/reviews/<user>/<branch>.md   (session strengths/weaknesses + asset ideas)
                     ──▶ prompt-example-curator ──▶ <outcomes>/guides/<user>.*  (OVERALL guide, grounded in whole store)
                     ──▶ asset-suggester ──▶ <outcomes>/suggestions/<user>.json (machine-readable: target_project + grounding)
       ──▶ /scaffold-asset ──▶ asset-architect ──▶ traces the real repo ──▶ a new skill/agent/hook/command/rule/script
```
(`<outcomes>` = `PROMPT_OUTCOMES_DIR`, default the sibling `../prompts-review-outcomes`.)

## Commands (`/name`)

| Command | Usage | Input | Outcome |
|---|---|---|---|
| `/configure` | `/configure [--project] [--journal <path>]` | OS + optional flags | Wires the `UserPromptSubmit` recorder hook into your Claude settings (global by default), self-tests it, auto-fixes issues. Logs land in the sibling `../prompts/`. Run once after cloning; re-run to repair. |
| `/analyse` | `/analyse [<file-or-dir> \| --project <name> \| --branch <name>] [--user <name>]` | **Default: the whole journal** (`../prompts`); or narrow to a file/dir, project, or branch | Runs the whole pipeline (all outputs under the outcomes dir `../prompts-review-outcomes/`): scores every prompt, writes a per-file review to `reviews/<user>/<branch>.md`, appends to `scores/<user>.jsonl`, compiles the **overall** `guides/<user>.*` from the full store, and updates machine-readable `suggestions/<user>.json`. Idempotent. |
| `/prompt-review` | `/prompt-review [<file-or-dir> \| --project <name> \| --branch <name>] [--user <name>]` | Same as `/analyse` | Back-compat alias of `/analyse` — identical behaviour. |
| `/review-asset` | `/review-asset [<asset-file-or-dir>] [--focus <type\|rubric>]` | An asset file, an asset dir, or a repo (default `./.claude`) | **Read-only audit** of existing skills/agents/hooks/commands/rules/scripts against the shared quality gate (frontmatter + anatomy + 7 rubrics + non-destructive permissions + model tier + verification). Runs `validate-frontmatter.py`, then judgment review; returns findings + score + **PASS/FAIL** with a fix each. Never edits — routes fixes to `/scaffold-asset`. |
| `/scaffold-asset` | `/scaffold-asset <suggestion-id \| inline need> [--repo <path>] [--confluence <url\|id>] [--docs <path>] [--code <glob>] [--prompts <log>] [--user <name>]` | A `suggestions/<user>.json` id (carrying `target_project` + `grounding`) or an inline need, plus optional grounding sources | Builds a **grounding brief** from repo code + CLAUDE.md/rules + Confluence pages + docs + raw prompts, then emits the right asset **type + placement** to the artifact anatomy **with a verification** — **only after you approve the draft**. |
| `/catalog` | `/catalog` | — | Prints this capability guide (commands, skills, agents with usage/input/outcome). |
| `/test` | `/test` | — | End-to-end tests the framework: runs `scripts/selftest.sh`, then drives every key skill/command over fixtures in an isolated `_selftest` sandbox and reports PASS/FAIL. Touches no real data. |

## Skills (auto-trigger on phrases, or invoked by a command)

| Skill | Usage / triggers | Input | Outcome |
|---|---|---|---|
| `prompt-critic` | "review/score/rate/critique this prompt" | One prompt (user or system), optional `session_context` of earlier turns | A machine-parseable **JSON contract** (score, verdict, `suggested_eval_criteria`, localized gaps) + a short Markdown summary and a rewrite. The scoring source of truth. |
| `prompt-example-curator` | "curate examples", "update my guide", "band these prompts" | prompt-critic output (or the score store) for a user | Bands each prompt **bad / good / excellent**, picks the most instructive real examples, and writes them (verbatim, with before→after rewrites) into `guides/<user>.md`. |
| `asset-suggester` | "suggest assets", "what could be a skill", "find reusable patterns" | The score store (+ `project`/`root`) + each prompt's optional `asset_hint` | Clusters recurring intents/tools/tasks into deduped, **machine-readable** candidates in `suggestions/<user>.json` — each with `target_project{name,root_path,git_remote,branches}` + `grounding{claude_md,rules_dir,code_globs}`. Proposes only — never builds. |
| `asset-architect` | "turn this into a skill", "should this be a hook or a rule", "scaffold an asset", "generate an artifact grounded in this confluence page / doc / code" | A suggestions candidate (or inline need); target repo defaults to the candidate's `root_path` | A **multi-source grounding consumer**: builds a grounding brief from repo code + CLAUDE.md/rules + Confluence + docs + raw prompts, picks asset **type + placement**, emits it to the **artifact anatomy** — addressing the 7 rubrics (correctness/latency/cost/security/observability/scale/reliability), non-destructive permissions, and a model tier — **with a verification**, then scaffolds **after approval**. |
| `prompt-journal` | "run the prompt pipeline", "analyse all my prompts" (the engine behind `/analyse`) | **Default: the whole journal** (`../prompts`), or a file/`--project`/`--branch` + a user | Orchestrates score → per-file review → store → **overall** guide → machine-readable suggestions, treating entries under one `branch=` header as one session/chain. |
| `configure` | "configure", "set up the hook", "fix my prompt journal hook" (the engine behind `/configure`) | OS + optional `--journal` / `--project` | Detects OS, runs `scripts/configure.*`, wires + self-tests the recorder hook, and reports `[OK]`/`[FIXED]`/`[ACTION]`. |
| `artifact-reviewer` | "review this skill/agent/hook", "audit my .claude assets", "does this follow best practices" (engine behind `/review-asset`) | an asset / dir / repo (default `.claude/`) | Read-only audit against the shared **quality gate** (frontmatter + anatomy + 7 rubrics + permissions + model + verification); scored findings + PASS/FAIL; routes fixes to `asset-architect`. |
| `catalog` | "help", "list commands/skills" (the engine behind `/catalog`) | — | Renders this catalog. |
| `test-framework` | "test the framework", "self-test", "verify the pipeline" (the engine behind `/test`) | fixtures under `tests/fixtures/` | Runs the harness + drives every skill/command in a `_selftest` sandbox, checks outcomes, tears down, reports PASS/FAIL. |

## Agents (subagents)

This repo defines **no repo-local subagents** (`.claude/agents/` is absent). The pipeline
runs through the skills above. Asset candidates that should become a subagent are proposed by
`asset-suggester` and scaffolded by `asset-architect`/`/scaffold-asset` — into the target
repo, not necessarily here.

## Typical flow

`/configure` once → work normally (prompts auto-record to `../prompts/`) → `/analyse --user <you>`
at end of day → read `../prompts-review-outcomes/guides/<you>.md` → optionally `/scaffold-asset` a recurring pattern.

## Non-command scripts (for reference)

| Script | Purpose |
|---|---|
| `scripts/record-prompt.{ps1,sh}` | The recorder hook itself — appends each prompt to `../prompts/<branch>.txt`. Wired by `/configure`; not run by hand. |
| `scripts/configure.{ps1,sh}` | OS-specific hook installer/repair invoked by `/configure`. |
| `scripts/render-guide.py` | Renders `guides/<user>.json` to Markdown + PDF + Word. |
| `scripts/selftest.sh` | Deterministic sandboxed self-test of the scripts + schemas; first step of `/test`. |
| `scripts/validate-frontmatter.py` | Deterministic frontmatter gate for skills/commands/agents; first step of `/review-asset` (wireable as a hook/CI gate). |
