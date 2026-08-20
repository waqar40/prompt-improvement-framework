# Prompt Journal — record, rate, and improve your prompts as a team

A **Claude Code plugin** for getting better at prompting, together. It **records every prompt
you send to Claude Code**, **scores each one** against a rubric distilled from Anthropic's
and OpenAI's guidance, and **builds a personal guide** for each teammate with real
before/after examples and the habits to build.

The whole point is a feedback loop: one prompt teaches you nothing; a few hundred logged
and honestly reviewed prompts show you your actual habits — the good ones to keep and the
lazy ones to kill.

> **Every `/command` in this README (`/configure`, `/analyse`, `/scaffold-asset`, …) is a
> Claude Code slash command.** Type it into the Claude Code chat prompt itself — **not**
> your OS terminal (bash/zsh/PowerShell). You need the [Claude Code CLI](https://docs.claude.com/en/docs/claude-code)
> installed. Only `scripts/render-guide.py` (Part D) is a real shell command — and even its
> Python dependencies are installed for you by `/configure`, not by hand.

---

## Quick start (3 steps)

1. **Add the marketplace and install the plugin** — inside any Claude Code session:
   ```
   /plugin marketplace add waqar40/prompt-improvement-framework
   /plugin install prompt-journal
   ```
   That's the entire setup. The `UserPromptSubmit` recorder hook wires itself automatically
   (`hooks/hooks.json`) — no settings.json editing, no `pip install`, no dependency hunting.
2. **Send any throwaway prompt** in any repo. Confirm a `<branch>.txt` file appeared under
   `~/.claude/prompt-journal/prompts/`. You're now recording automatically — nothing else to do.
   If nothing appears, run `/configure` — it self-tests the recorder and reports exactly what's wrong.
3. **Whenever you want feedback**, run `/analyse` (see [table below](#command-reference)).
   It scores everything you've recorded and writes/updates your personal guide.

That's the whole loop: **write prompts normally → `/analyse` → read your guide.** Everything
past this point is detail you can come back to.

<details>
<summary>Developing on this repo directly (not installing it as a plugin)</summary>

Clone it and add the clone itself as a marketplace source instead of the GitHub shorthand:
```bash
git clone https://github.com/waqar40/prompt-improvement-framework ~/prompt-journal
```
```
/plugin marketplace add ~/prompt-journal
/plugin install prompt-journal
```
See [Setup, in detail](#setup-in-detail) for the standalone `--legacy-hook` fallback if your
Claude Code version predates the plugin system.
</details>

---

## How it works

The plugin keeps **data and machinery separate — the plugin itself is machinery only.** Both
inputs and outputs live under your Claude home, not inside the plugin's installed files (which
Claude Code manages and can relocate on update), so nothing personal is ever committed. Beyond
the prompt text itself, it also records **which skills, subagents, and file-touching tools
actually ran as a result of that prompt** (with resolved paths) — so `/analyse` can grade with
real execution context, not just the words you typed:
- **INPUT** — raw prompt logs, default `~/.claude/prompt-journal/prompts/`. Override with
  `/configure --journal <path>` or `PROMPT_JOURNAL_DIR`.
- **OUTPUT** — `scores/`, `guides/`, `suggestions/`, `reviews/` all under
  `~/.claude/prompt-journal/prompts-review-outcomes/`. Override with `PROMPT_OUTCOMES_DIR`.

```
 You type a prompt
        │
        ▼
 UserPromptSubmit hook  ──►  per-branch log        scripts/record-prompt.{ps1,sh}
 (records it verbatim)       <journal>/<branch>.txt         (wired by hooks/hooks.json)
        │
        ▼
 (you work — Claude invokes skills/subagents/tools to act on the prompt)
        │
        ▼
 PostToolUse + Stop hooks ► ----- assets-used -----          scripts/record-tool-use.{ps1,sh}
 (buffer + flush what ran)   appended to that same entry      + record-turn-end.{ps1,sh}
        │
        ▼
 prompt-critic  ──────────►  <outcomes>/scores/<user>.jsonl   skill: rate each prompt
 (scores + rewrites,         (append-only)                     — using assets-used as
  assets-used as context)                                        context, never a score input
        │
        ▼
 prompt-example-curator ──►  <outcomes>/guides/<user>.{json,md,pdf,docx}   band + examples
 (curates the guide)
        │
        ▼
 asset-suggester  ────────►  <outcomes>/suggestions/<user>.json   cluster recurring work into
 (spots reusable patterns)                             skill/agent/hook/rule/command candidates
        │
        ▼
 /analyse <path>  ────────►  runs the whole pipeline over a log or the whole journal  (prompt-journal)
        ⋮
 /scaffold-asset  ────────►  decide type + placement, then build an asset   (skill: asset-architect)
 /review-asset    ────────►  read-only audit against the shared gate        (skill: artifact-reviewer)
 /fix-asset       ────────►  apply only the fully-specified findings        (skill: asset-fixer)
```
(`<journal>` default `~/.claude/prompt-journal/prompts`; `<outcomes>` default
`~/.claude/prompt-journal/prompts-review-outcomes`.)

The internal pieces that make this run, all in this plugin:

| Piece | What it is | Where |
|---|---|---|
| **Recorder hook** | Appends each prompt to a per-branch log file in the journal dir | `scripts/record-prompt.ps1` / `.sh`, wired by `hooks/hooks.json` |
| **Asset-use recorder hooks** | Buffer + flush which skills/subagents/tools ran as a result of that prompt (name + resolved path), appended as an `assets-used` block on the same entry | `scripts/record-tool-use.{ps1,sh}` (`PostToolUse`) + `scripts/record-turn-end.{ps1,sh}` (`Stop`), both wired by `hooks/hooks.json` |
| **`prompt-critic`** skill | Scores a prompt (D1–D10 design + E1–E4 evaluability), localizes gaps, rewrites it | `skills/prompt-critic/` |
| **`prompt-example-curator`** skill | Bands prompts bad/good/excellent and writes worked examples into the guide | `skills/prompt-example-curator/` |
| **`asset-suggester`** skill | Clusters recurring work across the journal into reusable-asset candidates | `skills/asset-suggester/` |
| **`asset-architect`** skill | Decides asset type + placement and scaffolds it (after your approval) | `skills/asset-architect/` |
| **`artifact-reviewer`** skill | Audits an existing asset against the same quality gate `asset-architect` builds to, incl. instructional semantics (contradiction/ambiguity/persona/cognitive-load/coverage/composition-conflict); read-only | `skills/artifact-reviewer/` |
| **`asset-fixer`** skill | Applies only the review findings that are fully specified (mechanical) — never authors new content | `skills/asset-fixer/` |
| **`prompt-journal`** skill | Runs record → score → curate → suggest end to end | `skills/prompt-journal/` |

You never need to invoke a skill directly — each has a slash command in front of it. That's
the table below.

---

## Command reference

Every command is typed into the **Claude Code chat prompt**, not a shell (`render-guide.py`
is the one exception — it's a normal Python script). "Input" lists every argument/flag and
what it means; "Outcome" is exactly what gets written or printed, so you know what to expect
before you run it.

### `/configure`

**What it does** — verifies (or repairs) the recorder after install: the `UserPromptSubmit`
hook itself is already wired automatically by the plugin's `hooks/hooks.json` — this command
makes sure the rest actually works (journal/outcomes dirs, self-test, PDF/Word rendering
deps). Safe to re-run any time.

| | |
|---|---|
| **Input** | Nothing required. Optional flags: `--journal <path>` (`-JournalDir <path>` on Windows) — put logs somewhere other than the default `~/.claude/prompt-journal/prompts`; `--legacy-hook` (`-LegacyHook`) — also patch `UserPromptSubmit` + `PostToolUse` + `Stop` hooks into `settings.json` by hand, only needed if you're running this repo standalone rather than as an installed plugin (`--project`/`--settings` imply it). |
| **Outcome** | Journal + outcomes dirs created if missing; executable bit fixed on macOS/Linux; the pinned PDF/Word guide-rendering deps (`scripts/requirements.txt`) installed if a Python is found and they're missing; a self-test confirming the recorder actually writes a log entry. With `--legacy-hook`, also registers/repairs all three recorder hooks in `settings.json` — `UserPromptSubmit` (`record-prompt`), `PostToolUse` (`record-tool-use`, matcher-scoped to asset-invocation tools), and `Stop` (`record-turn-end`) — removing stale/duplicate entries. Prints one line per check: `[OK]` (already correct), `[FIXED]` (it corrected something for you), `[OPTIONAL]` (only the PDF/Word deps couldn't be auto-installed — the rest of the pipeline, including the Markdown guide, is unaffected), or `[ACTION]` (you need to do one manual step — it tells you exactly what). |
| **When to run it** | Once, right after installing the plugin, to confirm it's working. Again any time prompts stop appearing in `~/.claude/prompt-journal/prompts/`, or `/analyse` reports it couldn't render PDF/Word. |

### `/analyse` (alias: `/prompt-review`)

**What it does** — the main pipeline: scores every prompt you've recorded and refreshes your
guide. Where a prompt's entry carries an `assets-used` block, prompt-critic uses it as grading
**context** (evidence for gaps it would flag anyway — never a separate scored dimension).
Idempotent — re-running never double-counts a prompt.

| | |
|---|---|
| **Input** | Optional **selector** (pick at most one) — a file/dir path (e.g. `~/.claude/prompt-journal/prompts/master.txt`), `--project <name>`, or `--branch <name>`. **Omit it entirely to analyse your whole journal** (the default, and the normal way to run it). Optional `--user <name>` — whose store/guide to update; defaults to your OS username. |
| **Outcome** | For each log processed: a per-file review at `<outcomes>/reviews/<user>/<branch>.md` (that session's strengths/weaknesses + asset opportunities, grounded in what actually ran where available). Across the whole run: new lines appended to the append-only score store `<outcomes>/scores/<user>.jsonl` (each carrying `assets_used`); your guide regenerated at `<outcomes>/guides/<user>.{json,md,pdf,docx}`; asset candidates refreshed at `<outcomes>/suggestions/<user>.json`. |
| **When to run it** | Regularly — weekly is a reasonable cadence. Narrow it (`--project`, `--branch`, a file) only when you want to re-check one slice without waiting on the whole journal. |

### `/scaffold-asset`

**What it does** — turns a recurring pattern (surfaced by `/analyse`) into a real, reusable
Claude Code asset: a skill, subagent, hook, slash command, memory rule, or script.

| | |
|---|---|
| **Input** | **Required**: a candidate id from `<outcomes>/suggestions/<user>.json` (e.g. `/scaffold-asset sg-014`), or a plain-English description of the need typed inline. Optional grounding flags: `--repo <path>` (target repo to scaffold into), `--confluence <url\|id>`, `--docs <path>`, `--code <glob>`, `--prompts <log\|user>`, `--user <name>`. |
| **Outcome** | First prints a **grounding brief** (what it read from the target repo's code/`CLAUDE.md`/rules, plus any Confluence/docs/prompts you pointed it at) and a **draft** of the asset — type, placement, and content. **It writes nothing until you approve the draft.** After approval: the new file is written to its canonical location (e.g. `.claude/skills/<name>/SKILL.md`) with a built-in verification (evals, output contract, or an exit-code test). |
| **When to run it** | When `/analyse` or `asset-suggester` flags a repeated pattern worth turning into an asset, or any time you want to hand-build one from a described need. |

### `/review-asset`

**What it does** — audits an *existing* skill/agent/hook/command/rule/script against the same
quality gate `/scaffold-asset` builds to — including **Section G**, the instructional-prose axis
(contradiction, ambiguity, persona consistency, cognitive load, semantic coverage, and
composition-conflict against every file the asset references). Read-only: it reports, it never edits.

| | |
|---|---|
| **Input** | Optional path to one asset file or a directory tree (default: the current repo's `.claude/` or plugin-root `commands/`/`skills/`/`agents/`, whichever exists). Optional `--focus <type\|rubric>` to narrow the audit to one asset type or one of the 7 quality rubrics (correctness/latency/cost/security/observability/scale/reliability). |
| **Outcome** | A severity-ranked findings report, a score, and a PASS/FAIL verdict, with a concrete suggested fix per finding — each finding tagged `mechanical` (fully specified, safe for `/fix-asset`) or needs-authoring (route to `/scaffold-asset` or a human). No files are modified. |
| **When to run it** | Before trusting an asset (yours or someone else's) in a real workflow, or periodically to catch drift. |

### `/fix-asset`

**What it does** — applies the `mechanical` findings from a `/review-asset` report verbatim: a
dangling reference removed, an invalid frontmatter key dropped, a stale table row deleted. It never
writes new prose, sections, or verifications — anything that needs judgment is skipped and reported,
not guessed at. The write-capable counterpart to the read-only `/review-asset`.

| | |
|---|---|
| **Input** | An asset file, and optionally a findings report (`--findings <path\|json>`) — if omitted, it runs `/review-asset` on the target first. |
| **Outcome** | The mechanical findings are fixed in place; everything else is listed as `SKIPPED (not auto-fixable: …)` with a pointer to `/scaffold-asset`. `scripts/validate-frontmatter.py` is re-run on what changed. |
| **When to run it** | Right after `/review-asset` flags mechanical findings you want cleared without a full scaffolding pass. |

### `/catalog`

**What it does** — prints the full capability guide for this repo: every command, skill, and
agent, reconciled against what's actually installed on disk (so it can't drift out of date).

| | |
|---|---|
| **Input** | None. |
| **Outcome** | A printed reference table (usage, input, outcome) for every command/skill/agent — useful as a live index whenever you forget what's available. |
| **When to run it** | Any time you want "what can this repo do?" answered without leaving Claude Code. |

### `/test`

**What it does** — end-to-end self-test of the whole framework, in complete isolation from
your real data.

| | |
|---|---|
| **Input** | None. |
| **Outcome** | Runs `scripts/selftest.sh` (deterministic recorder/configure/parser/renderer checks), then drives `prompt-critic`, `/analyse` (all selector forms), `asset-suggester`, `asset-architect` (draft-only), `artifact-reviewer` + `asset-fixer` (against the deliberately defective `tests/fixtures/assets/bad-skill/` fixture), and `/catalog` over fixtures under a throwaway `_selftest` user. Prints a PASS/FAIL checklist, then tears down every test artifact and temp dir it created. **Never touches your real journal, scores, guide, suggestions, or settings.** |
| **When to run it** | After changing any script, skill, or fixture in this repo, to confirm nothing broke. |

### `scripts/render-guide.py` *(shell command, not a slash command)*

**What it does** — regenerates the human-readable views of your guide from its JSON source.
`/analyse` already calls this for you; run it by hand only if you edited the JSON directly or
want to re-render without a full `/analyse` pass.

| | |
|---|---|
| **Input** | Required positional arg: path to `<outcomes>/guides/<user>.json`. Optional flag to render just one format: `--md`, `--pdf`, or `--docx` (omit to render all three). PDF/Word need `reportlab` + `python-docx`, pinned in `scripts/requirements.txt` (`reportlab==4.1.0`, `python-docx==1.1.2`) — **`/configure` already installs these for you**; only run `pip install -r scripts/requirements.txt` yourself if you skipped `/configure` or it reported `[OPTIONAL]`. The Markdown view needs neither package. (reportlab is pinned below 4.2 because 4.2+ calls `hashlib.md5(usedforsecurity=...)`, a keyword only supported on Python 3.9+ — it breaks under Python 3.8.) |
| **Outcome** | Writes `<user>.md`, `<user>.pdf`, and/or `<user>.docx` next to the JSON file in `<outcomes>/guides/`. If a dependency is missing for a requested format, that format is skipped with a one-line `WARNING` (naming the fix) instead of a crash — the other formats still write. |
| **When to run it** | Rarely — only for manual re-renders. |

```bash
python scripts/render-guide.py ~/.claude/prompt-journal/prompts-review-outcomes/guides/<user>.json          # all three: MD + PDF + DOCX
python scripts/render-guide.py ~/.claude/prompt-journal/prompts-review-outcomes/guides/<user>.json --pdf     # just one
```

---

## Setup, in detail

Only read this if the quick start didn't just work, or you want to know what it's doing under
the hood.

### 1. Add the marketplace and install the plugin

Inside a Claude Code session, anywhere:

```
/plugin marketplace add waqar40/prompt-improvement-framework
/plugin install prompt-journal
```

This fetches the plugin, registers `hooks/hooks.json`, and makes every `/command` in this
README available. The `UserPromptSubmit` recorder hook is **active immediately** — no
settings.json edit, no restart required for the hook itself (Claude Code may prompt you to
reload the session to pick up the new commands/skills).

Everyone keeps **their own journal** — logs, scores, and guide are per-person, written under
your own `~/.claude/prompt-journal/` regardless of who else has the plugin installed.

### 2. Run `/configure` to confirm it's working

```
/configure
```

See the [command reference](#configure) above for exactly what it checks and prints. It is
**idempotent** — safe to re-run any time a prompt stops getting logged. You only need to act
when it prints an `[ACTION]` line (e.g. "install `jq` or `python3`") — it tells you the exact
step.

<details>
<summary>Standalone fallback (not installing via the plugin system)</summary>

If you're developing on a clone of this repo directly rather than installing it as a plugin —
or your Claude Code version predates the plugin system — run `/configure --legacy-hook`
(`-LegacyHook` on Windows) to patch all three recorder hooks (`UserPromptSubmit`,
`PostToolUse`, `Stop`) into `~/.claude/settings.json` by hand instead, then restart Claude Code
/ start a new session so it reloads `settings.json`.

You can also add the hooks manually, adjusting the script paths to your clone (this is the
same shape `hooks/hooks.json` declares for a plugin install):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File \"<clone>/scripts/record-prompt.ps1\"", "timeout": 15 } ] }
    ],
    "PostToolUse": [
      { "matcher": "Skill|Task|Read|Edit|Write|NotebookEdit",
        "hooks": [ { "type": "command", "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File \"<clone>/scripts/record-tool-use.ps1\"", "timeout": 10 } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File \"<clone>/scripts/record-turn-end.ps1\"", "timeout": 10 } ] }
    ]
  }
}
```
macOS / Linux: use `"bash \"<clone>/scripts/record-prompt.sh\""` etc. instead, and run
`chmod +x scripts/record-*.sh`. The bash recorders need `jq` or `python3` on `PATH`. Omitting
the `PostToolUse`/`Stop` hooks still works — you just won't get `assets-used` blocks.
</details>

### 3. Verify

Send a throwaway prompt in any repo, then check that a `<branch>.txt` appeared under
`~/.claude/prompt-journal/prompts/` with a `===== [timestamp] branch=… =====` entry.
(`/configure` already self-tests this, so it should just work.) That's it — recording is now
automatic.

> **Do not paste secrets into prompts.** Prompts are stored verbatim in plain-text logs.
> Treat the journal like any other source-controlled text: no credentials, tokens, or
> customer data. This is a security requirement, not a suggestion.

---

## Daily use

Just work. Every prompt you submit is appended to a log under `~/.claude/prompt-journal/prompts/`,
named after the current context, resolved in this order (slashes become hyphens in the filename):

1. **git branch** → `feature/PROJ-1234_x` becomes `feature-PROJ-1234_x.txt`;
2. **no branch → session name** (from `CLAUDE_SESSION_NAME`, or a named session) →
   `session/example-session` becomes `session-example-session.txt`;
3. **no session name → repo root folder** (or the working directory name) →
   `repo/my-app` becomes `repo-my-app.txt`.

Slash commands (`/build`, `/init`) are recorded too.

**What ran gets recorded alongside what you typed.** Once Claude finishes responding, if it
invoked any skills, subagents, or Read/Edit/Write/NotebookEdit tools, an `assets-used` block
(name + resolved path for each) is appended to that same entry — automatically, no action
needed. Turns that only used other tools (Bash, Grep, search, …) or no tools at all simply get
no block; that's normal.

**Logs are append-only history — never edit them.** Their sloppiness is the data — and so is
the `assets-used` block once it's written; it's machine-recorded, not yours to edit, but it's
still part of the log's history.

---

## What the rubric checks

`prompt-critic` — the skill `/analyse` calls to score each prompt — checks two layers (full
detail in `skills/prompt-critic/references/rubric.md`):

- **Layer 1 — Design:** clarity & explicit action verb (D1), specificity & constraints
  (D2), output format (D3), context/motivation (D4), grounding (D5), examples (D6),
  positive framing (D7), uncertainty handling (D8), decomposition fit (D9), structural
  economy — no over-engineering (D10).
- **Layer 2 — Evaluability:** is success defined (E1), measurable (E2), multidimensional
  (E3), and are failure modes anticipated (E4).

It produces a JSON contract (score 0–100, verdict `STRONG/ADEQUATE/WEAK/POOR/BLOCKED`, a
per-dimension finding with evidence, a rewritten prompt, and suggested eval criteria) then
a short Markdown summary.

**Short prompts and chains are handled fairly.** Most real prompts are terse follow-up turns
that lean on session context (`"push it"`, `"are we good to merge?"`). The critic scores these
as **chain steps**: it judges them against what the session already resolved and **never
penalizes brevity** — a one-word `"yes"` can be an excellent turn. It only flags a reference
the session genuinely left ambiguous, an undefined verb, or an untestable success word. See
`skills/prompt-critic/references/conversational-chains.md`.

**Real execution context sharpens the grade, without becoming a new dimension.** When an
entry has an `assets-used` block — recorded automatically after each turn (see
[Daily use](#daily-use)) — the critic reads it as evidence, e.g. a "fix"/"add" prompt whose
recorded tools show only reads and no edits is corroborating evidence for an E1/E2 gap it
would otherwise have to infer blind. It never scores the tool use itself, and it never
penalizes a well-specified prompt just because the agent decided no change was needed.

---

## See it in action: one bad prompt, one good prompt

Two real prompts from this repo's own test fixtures (`tests/fixtures/logs/feature-DEMO-2_beta.txt`
and `feature-DEMO-1_alpha.txt`), scored by `prompt-critic` exactly as `/analyse` would score
yours. This is the **complete** rubric table, not a summary — every dimension is graded and shown,
including the ones marked `n/a`, because that's what you'll see for every prompt in your own guide.

### Example 1 — a vague prompt (band: `bad` · score 56/100 · verdict `WEAK`)

> **Prompt as sent:** `version-control it to the shared repo`
> *(a follow-up turn — the previous turn in that session was `commit this`)*

| # | Dimension | Verdict | Severity | Evidence |
|---|---|---|---|---|
| D1 | Clarity & explicitness | Partial | Major | "version-control" names a *category* of git operations, not one of them |
| D2 | Specificity & constraints | Partial | Major | "to the shared repo" names a target, but not which remote or branch |
| D3 | Output format & length | n/a | — | no meaningful output format beyond the git operation itself |
| D4 | Context & motivation | n/a | — | motivation wouldn't change which git command applies |
| D5 | Grounding / reference | n/a | — | no factual grounding needed |
| D6 | Examples (show-not-tell) | n/a | — | no example needed for a one-line directive |
| D7 | Positive framing | Met | — | phrased as what to do, not what to avoid |
| D8 | Uncertainty handling | n/a | — | not a factual-risk task |
| D9 | Decomposition fit | Met | — | a single step, not artificially split |
| D10 | Structural economy | Met | — | brief, not over-engineered |
| E1 | Success is defined | Gap | Major | no notion of "done" — a commit-only, a push, and an opened PR are all consistent with the wording |
| E2 | Criteria are measurable | Partial | Major | can't binary-check "version-controlled" without knowing which git action was meant |
| E3 | Multidimensional coverage | n/a | — | a single quality axis is at stake here |
| E4 | Failure modes anticipated | n/a | — | no new failure mode beyond the verb ambiguity already scored |

**Rewrite `/analyse` would suggest:**
`commit the deploy.sh change with a message describing the --dry-run flag, then push it to origin/main`

**The lesson:** name the actual git command (commit / push / open a PR) — a category word like
"version-control" forces the model to guess which one you meant.

### Example 2 — a strong prompt (band: `excellent` · score 100/100 · verdict `STRONG`)

> **Prompt as sent:** `Add a --dry-run flag to scripts/deploy.sh that prints each command it
> would run, prefixed with "[dry-run]", and exits 0 without executing anything. Acceptance:
> bash scripts/deploy.sh --dry-run makes no network calls and prints one line per docker/kubectl
> command.`

| # | Dimension | Verdict | Severity | Evidence |
|---|---|---|---|---|
| D1 | Clarity & explicitness | Met | — | one unambiguous instruction, led by the action verb "Add" |
| D2 | Specificity & constraints | Met | — | scope is `scripts/deploy.sh`; the boundary ("without executing anything") is explicit |
| D3 | Output format & length | Met | — | "prints one line per docker/kubectl command" pins the output shape |
| D4 | Context & motivation | n/a | — | the *why* wouldn't change the implementation of an already well-specified flag |
| D5 | Grounding / reference | n/a | — | the agent can read `deploy.sh` directly; no external source of truth needed |
| D6 | Examples (show-not-tell) | n/a | — | the format is fully described without needing an example |
| D7 | Positive framing | Met | — | every instruction says what TO do (print, prefix, exit 0) |
| D8 | Uncertainty handling | n/a | — | a verifiable coding task, no hallucination risk |
| D9 | Decomposition fit | Met | — | simple enough for one prompt, not artificially split |
| D10 | Structural economy | Met | — | no over-engineering, no dead instructions |
| E1 | Success is defined | Met | — | the acceptance line defines what correct output is |
| E2 | Criteria are measurable | Met | — | "makes no network calls and prints one line per ... command" is a binary check |
| E3 | Multidimensional coverage | Met | — | both correctness (no execution) and format (prefix, one line each) are covered |
| E4 | Failure modes anticipated | Met | — | "exits 0 without executing anything" directly guards the main failure mode |

**The lesson:** no rewrite needed — imitate this. A single unambiguous instruction, an exact
output format, and a testable acceptance condition up front leave nothing for the model to guess at.

### What `/analyse` actually writes for these two prompts

Running `/analyse` over a log containing them writes to three places under
`<outcomes>` (default `~/.claude/prompt-journal/prompts-review-outcomes`):

1. **One append-only line each in `<outcomes>/scores/<user>.jsonl`:**
   ```json
   {"date":"2026-08-11","project":"beta","branch":"feature/DEMO-2_beta","prompt_excerpt":"version-control it to the shared repo","prompt_kind":"chain_step","score":56,"verdict":"WEAK","band":"bad","top_dimensions":["D1","E1"]}
   {"date":"2026-08-10","project":"alpha","branch":"feature/DEMO-1_alpha","prompt_excerpt":"Add a --dry-run flag to scripts/deploy.sh...","prompt_kind":"one_shot","score":100,"verdict":"STRONG","band":"excellent","top_dimensions":[]}
   ```
2. **A per-file review** at `<outcomes>/reviews/<user>/<branch-slug>.md` — each prompt's session
   rolled into Strengths / Weaknesses / Asset opportunities (see [Turning recurring work into
   reusable assets](#turning-recurring-work-into-reusable-assets)).
3. **The compiled guide** at `<outcomes>/guides/<user>.md` — Example 1 lands in **"Anti-patterns
   to kill"** with the full table above plus the before→after rewrite; Example 2 lands in
   **"What excellent looks like"** with the full table and no rewrite ("imitate this"). See
   [Your guide](#your-guide) below for the complete rendered format.

That's the whole loop, end to end: what you type → a graded table like the ones above → a banded
example in your guide → a habit you can apply before your next prompt.

---

## Your guide

`~/.claude/prompt-journal/prompts-review-outcomes/guides/<user>.md` is your living,
personalised output, written by `/analyse`. It has:

- a **Snapshot** — prompts reviewed, band counts (excellent/good/bad), and trend vs. last
  time;
- **What excellent looks like** — your own strongest prompts, with why they work;
- **Good, one fix away** — near-misses with the single high-leverage fix;
- **Anti-patterns to kill** — your weakest prompts, each with a before→after rewrite;
- **Habits to build** and **Habits you already have**.

Every example is one of *your* real prompts, quoted verbatim with source and date. The
guide is regenerated by merging — it keeps what still teaches, adds new examples, and
retires stale ones. Format is fixed in
`skills/prompt-example-curator/references/guide-format.md`.

**Human-friendly formats.** The guide has one structured source, `<outcomes>/guides/<user>.json`,
and three rendered views — **Markdown, PDF, and Word** — produced by
[`scripts/render-guide.py`](#scriptsrender-guidepy-shell-command-not-a-slash-command) (above).
Each reviewed prompt renders a **rubric scorecard** (every D1–D10 / E1–E4 dimension marked
Met / Partial / Missing / n-a, with evidence) and a **transformation table** (each gap →
a concrete rewrite + the principle it teaches).

---

## Turning recurring work into reusable assets

Reviewing prompts also surfaces **what you keep doing** — and repeated work is a signal to
build a reusable Claude Code asset. `/analyse` records those signals; two commands act on
them (see the [reference table](#command-reference) for their exact input/outcome):

- **`asset-suggester`** (runs automatically inside `/analyse`) clusters recurring
  intents/tools/tasks across your whole journal into candidates in `suggestions/<user>.json`
  — each typed provisionally as a **skill / subagent / hook / slash command / rule / script**,
  with the evidence (your real repeated prompts), a proposed trigger, and where it should live.
- **`/scaffold-asset <id>`** makes the authoritative call: applies a decision matrix (grounded
  in Anthropic's guidance — see `skills/asset-architect/references/sources.md`),
  localizes placement by reading the **target repo's `CLAUDE.md` + `.claude/rules/`**, drafts
  the asset to Anthropic's authoring standards, and **writes it only after you approve**.
- **`/review-asset`** audits an asset (new or old) against the same quality gate, any time you
  want a second opinion — including instructional-semantics checks (Section G: contradiction,
  ambiguity, persona consistency, cognitive load, semantic coverage, composition-conflict).
- **`/fix-asset`** applies the review's `mechanical` findings verbatim (a dangling reference, an
  invalid frontmatter key) without a full scaffolding pass; anything needing judgment is routed
  back to `/scaffold-asset`.

The guiding principle: *repetition tells you to capture a need; the signal tells you the type* —
a repeated **procedure** → skill, a **fact** → CLAUDE.md/rule, a **"whenever X" guarantee** →
hook (memory only steers; hooks enforce), an **isolated task** → subagent. `asset-architect`
complements your global `~/.claude/rules/sdlc-asset-authoring.md` and always scaffolds into the
**target** repo you point it at, never into this plugin itself.

---

## Rolling it out to the team

- **Everyone installs their own copy of the plugin.** Each teammate runs
  `/plugin marketplace add waqar40/prompt-improvement-framework` and `/plugin install
  prompt-journal` — no shared clone or shared install to coordinate. Each person's prompts
  land in **their own** `~/.claude/prompt-journal/prompts/` (relocate with `--journal <path>`
  or `PROMPT_JOURNAL_DIR`), and scores/guides/suggestions are keyed by username under their own
  outcomes dir (`<outcomes>/scores/<user>.jsonl`, `<outcomes>/guides/<user>.*`,
  `<outcomes>/suggestions/<user>.json`) — nothing to collide on, and `PROMPT_OUTCOMES_DIR` can
  point anywhere per person (a shared network drive, for instance, if you want to compare directly).
- **Share the method, compare the guides.** The guides are the interesting artifact — swap
  them in a team channel, compare recurring gaps, and turn the sharpest before/after
  examples into shared prompting standards.
- **Keep the rubric stable.** Scores are only comparable over time if the rubric, band
  mapping, and guide format don't drift. Change them deliberately, in one place, and note
  it — see `CLAUDE.md`.
- **Calibrate before trusting scores as a gate.** If you wire `prompt-critic` into CI,
  hand-label ~50–100 prompts strong/weak first and check agreement before believing the
  number (`skills/prompt-critic/references/usage-and-integration.md`).

---

## Testing the framework

Run **`/test`** (see the [reference table](#test)) to verify everything end to end, in an
isolated sandbox that never touches your real journal, settings, scores, guide, or
suggestions. The underlying script harness alone is CI-friendly:

```bash
bash scripts/selftest.sh   # exits non-zero if any check fails
```

## Repo map

Data lives under your Claude home, never inside the plugin's installed files (which Claude
Code manages and can relocate on update).

```
~/.claude/
├── prompt-journal/                   ← DATA (default location, both INPUT and OUTPUT)
│   ├── prompts/                          ← INPUT: raw per-branch prompt logs (append-only)
│   │   └── <branch>.txt
│   └── prompts-review-outcomes/          ← OUTPUT: everything /analyse produces
│       ├── scores/<user>.jsonl               append-only score store (project, root, branch, score, band, …)
│       ├── guides/<user>.{json,md,pdf,docx}  structured guide (json = source of truth) + rendered views
│       ├── suggestions/<user>.json           reusable-asset candidates (machine-readable)
│       └── reviews/<user>/<branch>.md        per-file session reviews (strengths/weaknesses + asset opportunities)
└── plugins/repos/.../prompt-improvement-framework/   ← THE PLUGIN (machinery only; installed/managed by Claude Code)
    .claude-plugin/plugin.json        plugin manifest (name, version, description)
    .claude-plugin/marketplace.json   self-listing marketplace (lets `/plugin marketplace add` target this repo directly)
    hooks/hooks.json                  wires the recorder hooks automatically (UserPromptSubmit/PostToolUse/Stop)
    *_ANNOTATED.md                    hand/assisted prompt reviews (legacy format)
    scripts/configure.{ps1,sh}        dirs + self-test + optional deps (the /configure command)
    scripts/record-prompt.{ps1,sh}    recorder hook (writes the logs; drops a per-turn marker)
    scripts/record-tool-use.{ps1,sh}  buffers asset invocations for the current turn (PostToolUse hook)
    scripts/record-turn-end.{ps1,sh}  flushes the buffer into an assets-used block (Stop hook)
    scripts/render-guide.py           JSON guide -> Markdown + PDF + Word renderer
    scripts/selftest.sh               deterministic sandboxed self-test (first step of /test)
    scripts/validate-frontmatter.py   deterministic frontmatter gate (first step of /review-asset)
    tests/fixtures/                   sample logs + guide used by the /test play
        assets/bad-skill/                 a deliberately defective skill (mechanical + needs-authoring findings)
    skills/prompt-critic/             scoring rubric + rewrite (+ optional asset_hint)
    skills/prompt-example-curator/    banding + guide curation
    skills/asset-suggester/           clusters recurring work into asset candidates
    skills/asset-architect/           multi-source grounding consumer: type + placement + scaffold
        references/artifact-anatomy.md      the skeleton of each emitted artifact (skill/agent/hook/…)
        references/grounding-sources.md     how it grounds from code, CLAUDE.md/rules, Confluence, prompts, docs
        references/quality-gate.md          the SHARED build+review checklist + rubric scorecard (sections A-G)
        references/semantic-consistency.md  Section G — contradiction/ambiguity/persona/cognitive-load/coverage/composition
        references/verification-harness.md  the evals.json schema + grader types behind Section F
    skills/artifact-reviewer/         read-only audit of existing assets against the quality gate
    skills/asset-fixer/               applies only the review's fully-specified (mechanical) findings
    skills/prompt-journal/            end-to-end pipeline
    skills/configure/                 OS-detect + run the right configurator
    skills/catalog/                   capability catalog (commands/skills/agents)
    skills/test-framework/            the /test play (end-to-end framework test)
    commands/                         /analyse /prompt-review /scaffold-asset /review-asset /fix-asset /configure /catalog /test
    CLAUDE.md                         guidance for Claude working in this repo
```

If you cloned this repo for development instead of installing it via the marketplace, the
plugin directory above is just the clone root — same layout, different parent path.

## Troubleshooting

- **No log file appears** — just re-run `/configure`; it self-tests the recorder directly
  (which exits silently on any error so it never blocks your prompt) and reports exactly
  what's wrong. If the plugin was only just installed, start a new session first so Claude
  Code picks up `hooks/hooks.json`.
- **Everything lands in `no-branch.txt`** — you were not on a git branch (detached HEAD or
  a non-git directory). Expected.
- **`bash: python3: command not found`** — install `jq` or `python3`; the recorder needs
  one to parse the hook JSON.
- **Running standalone (not via the plugin system) and nothing records** — run
  `/configure --legacy-hook` to patch all three recorder hooks into `settings.json` by hand,
  then restart Claude Code so it reloads settings.
- **Prompts record but `assets-used` blocks never appear** — confirm `PostToolUse` and `Stop`
  hooks are wired (`/configure` prints them under `[OK]`/`[FIXED]`); if you're standalone, they
  need `--legacy-hook` too (`UserPromptSubmit` alone doesn't cover them). Turns that only used
  Bash/Grep/other non-whitelisted tools, or no tools at all, correctly get no block — that's
  not a bug.
