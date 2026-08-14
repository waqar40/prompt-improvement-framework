---
name: prompt-journal
description: Use to run the end-to-end prompt-journal pipeline over recorded logs — by default the WHOLE journal (every log across every project/branch), or narrowed to one project, branch, or file. Scores every prompt with prompt-critic (treating the entries under one branch as one session/chain), writes a per-file review, appends results to the per-user score store, compiles an overall guide via prompt-example-curator, then refreshes machine-readable asset suggestions via asset-suggester. Triggers include "review my prompt journal", "run the prompt pipeline", "analyse today's prompts", "analyse all my prompts", "score this log and update my guide", and the /analyse and /prompt-review commands.
---

# Prompt Journal Pipeline

Orchestrates the loop: **recorded log(s) → prompt-critic scoring → per-file review + score store
→ prompt-example-curator (compiled overall guide) → asset-suggester (machine-readable
candidates)**. This skill owns the run; the rubric lives in `prompt-critic`, banding/guide logic
in `prompt-example-curator`, and asset clustering in `asset-suggester` — invoke those, do not
reimplement them.

**Analyse everything by default.** With no selector, process the entire journal — every `*.txt`
across every project and branch. The per-file reviews are the local outcome; the score store is
the record that lets the guide be a **compiled, grounded** view of the user's real overall state.

## Inputs

- `selector` (optional): what to analyse. Exactly one of:
  - a **path** — a log file or a directory of logs;
  - `--project <name>` — only logs recorded for that project (matches the `project=` header);
  - `--branch <name>` — only the log(s) for that branch;
  - a bare filename or branch that maps to a file.
  - **Omitted → the whole journal dir** (default): the sibling `../prompts` beside the clone, or
    `PROMPT_JOURNAL_DIR` if set.
- `user` (required): whose store/guide/reviews to update (e.g. `waqar.aziz`). Defaults to the OS user.
- **Outputs live OUTSIDE the repo.** Resolve the **outcomes dir** `<outcomes>` = `PROMPT_OUTCOMES_DIR`
  if set, else the sibling `../prompts-review-outcomes` beside the clone. All outputs are written
  under it: `<outcomes>/scores/`, `<outcomes>/guides/`, `<outcomes>/suggestions/`, `<outcomes>/reviews/`.
  Create the subdir if missing. (Inputs come from the journal dir; outputs go to the outcomes dir —
  the framework repo itself stays data-free.)

## Workflow

### Step 1 — Resolve the selection and parse into sessions
Resolve `selector` to a set of log files (default: every `*.txt` in the journal dir). For
`--project`/`--branch`, filter files by reading their headers. Parse each entry header:

```
===== [<timestamp>] branch=<id> [project=<name>] [root=<abs-path>] =====
```

Parse it with this (validated) regex — `project`/`root` are optional groups so older logs
still parse, and `root` is captured last so a path with spaces is safe:

```
^===== \[(?P<ts>.*?)\] branch=(?P<branch>\S+)(?: project=(?P<project>\S+))?(?: root=(?P<root>.+?))? =====$
```

`project=`/`root=` are **optional** (older logs omit them — degrade gracefully: project/root
`unknown`). **Group entries by
`branch`; that group in timestamp order is one session (chain).** Carry each session's `project`
and `root` forward — they feed the review, the store, and the suggestions metadata.

### Step 2 — Score each turn with prompt-critic
For each entry invoke **`prompt-critic`** with the prompt, passing all earlier same-branch entries
as `session_context` (follow-ups are chain steps — never penalized for brevity). Collect each JSON
result with its source file, project, root, branch, timestamp, `prompt_kind`, and any `asset_hint`.

### Step 3 — Append to the score store
Append one line per result to `<outcomes>/scores/<user>.jsonl` (create if missing): `{date, source,
project, root, branch, prompt_excerpt, prompt_kind, score, verdict, band, top_dimensions, asset_hint}`.
Append-only — **never rewrite past scores.** Skip entries already scored (match timestamp + prompt).

### Step 4 — Write a per-file review (the local outcome)
For **each processed file**, write `<outcomes>/reviews/<user>/<branch-slug>.md` (overwrite that file's review
each run). Because a file's prompts are one related session, review them together:
- header: file, `project`, `branch`, `root`, date range, prompts reviewed, band counts;
- a per-prompt table: excerpt · kind · score · band · top gap;
- **Strengths** and **Weaknesses** for this session (rolled from the rubric dimensions);
- **Asset opportunities** — skills/agents/hooks/commands/rules this related work suggests, each
  naming the proposed type and the `<outcomes>/suggestions/<user>.json` candidate id + `/scaffold-asset <id>`.
Keep it verbatim-grounded (quote real prompts); do not invent.

### Step 5 — Compile the overall guide (grounded in the whole store)
Invoke **`prompt-example-curator`** with **all** results for this `user` read from
`<outcomes>/scores/<user>.jsonl` (not just this run) so the guide's snapshot, strengths, weaknesses,
and `coverage` (files/projects/date range) reflect the user's **real overall state**. Update
`<outcomes>/guides/<user>.json`, then render md/pdf/docx (all under `<outcomes>/guides/`). Merge, don't clobber.

### Step 6 — Refresh machine-readable asset suggestions
Invoke **`asset-suggester`** with this run's results (incl. `asset_hint`s, `project`, `root`) and
`<outcomes>/scores/<user>.jsonl`. It clusters recurrence across the whole store and records candidates in
`<outcomes>/suggestions/<user>.json` with `target_project{name,root_path,git_remote,branches}` and
`grounding{claude_md,rules_dir,code_globs}` so `asset-architect` can later trace the real repo.
Idempotent — no duplicates.

### Step 7 — Report
Summarize: files processed (and the selector used), entries scored, per-file reviews written,
store lines added, overall guide snapshot deltas, and new/updated asset suggestions.

## Constraints

- DEFAULT to the whole journal; only narrow when a `selector` is given.
- Inputs come from the journal dir (`../prompts`); ALL outputs go under the outcomes dir
  (`../prompts-review-outcomes`, or `PROMPT_OUTCOMES_DIR`) — NEVER write scores/guides/suggestions/
  reviews inside the framework repo.
- NEVER edit the raw journal logs — append-only source data in the journal dir (sibling `../prompts`).
- ALWAYS pass earlier same-branch turns as `session_context`; the common case is short chain steps.
- ALWAYS append to the score store; never overwrite or reorder prior entries.
- Per-file reviews are the local outcome; the guide is the **compiled overall** view — keep it
  grounded in the full store, never in a single run.
- Delegate scoring to `prompt-critic`, banding/guide to `prompt-example-curator`, asset clustering
  to `asset-suggester`; keep rubric, bands, guide format, and suggestion schema consistent.
- Keep the pipeline idempotent — re-running must not double-count entries or duplicate suggestions.
