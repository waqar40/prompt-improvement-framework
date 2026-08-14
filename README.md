# Prompt Journal — record, rate, and improve your prompts as a team

A lightweight system for getting better at prompting, together. It **records every prompt
you send to Claude Code**, **scores each one** against a rubric distilled from Anthropic's
and OpenAI's guidance, and **builds a personal guide** for each teammate with real
before/after examples and the habits to build.

The whole point is a feedback loop: one prompt teaches you nothing; a few hundred logged
and honestly reviewed prompts show you your actual habits — the good ones to keep and the
lazy ones to kill.

> **Every `/command` in this README (`/configure`, `/analyse`, `/scaffold-asset`, …) is a
> Claude Code slash command.** Type it into the Claude Code chat prompt itself — **not**
> your OS terminal (bash/zsh/PowerShell). You need the [Claude Code CLI](https://docs.claude.com/en/docs/claude-code)
> installed. Only `scripts/render-guide.py` (Part D) is a real shell command.

---

## Quick start (4 steps)

1. **Clone the repo** somewhere stable — everyone keeps their own clone and their own journal.
   ```bash
   git clone <this-repo-url> ~/prompt-journal
   ```
2. **Open a Claude Code session in that clone** and run the setup command:
   ```bash
   cd ~/prompt-journal
   claude
   ```
   ```
   /configure
   ```
   This is the entire setup — see [`/configure`](#configure) below for exactly what it does.
3. **Restart Claude Code** (new session) so it picks up the change, then send any throwaway
   prompt in any repo. Confirm a `<branch>.txt` file appeared in the sibling `../prompts/`
   folder. You're now recording automatically — nothing else to do.
4. **Whenever you want feedback**, run `/analyse` (see [table below](#command-reference)).
   It scores everything you've recorded and writes/updates your personal guide.

That's the whole loop: **write prompts normally → `/analyse` → read your guide.** Everything
past this point is detail you can come back to.

---

## How it works

The repo keeps **data and machinery separate — the framework repo is machinery only.** Both
inputs and outputs live in sibling folders *beside* the clone, so nothing personal is ever
committed:
- **INPUT** — raw prompt logs in `../prompts/` (e.g. `D:/code/prompts`). Override with
  `/configure --journal <path>` or `PROMPT_JOURNAL_DIR`.
- **OUTPUT** — `scores/`, `guides/`, `suggestions/`, `reviews/` all under
  `../prompts-review-outcomes/`. Override with `PROMPT_OUTCOMES_DIR`.

```
 You type a prompt
        │
        ▼
 UserPromptSubmit hook  ──►  per-branch log        scripts/record-prompt.{ps1,sh}
 (records it verbatim)       ../prompts/<branch>.txt
        │
        ▼
 prompt-critic  ──────────►  ../prompts-review-outcomes/scores/<user>.jsonl   skill: rate each prompt
 (scores + rewrites)         (append-only)
        │
        ▼
 prompt-example-curator ──►  ../prompts-review-outcomes/guides/<user>.{json,md,pdf,docx}   band + examples
 (curates the guide)
        │
        ▼
 asset-suggester  ────────►  ../prompts-review-outcomes/suggestions/<user>.json   cluster recurring work into
 (spots reusable patterns)                             skill/agent/hook/rule/command candidates
        │
        ▼
 /analyse <path>  ────────►  runs the whole pipeline over a log or the ../prompts dir  (prompt-journal)
        ⋮
 /scaffold-asset  ────────►  decide type + placement, then build an asset   (skill: asset-architect)
```

The internal pieces that make this run, all in this repo:

| Piece | What it is | Where |
|---|---|---|
| **Recorder hook** | Appends each prompt to a per-branch log file in the sibling `../prompts/` | `scripts/record-prompt.ps1` / `.sh` |
| **`prompt-critic`** skill | Scores a prompt (D1–D10 design + E1–E4 evaluability), localizes gaps, rewrites it | `.claude/skills/prompt-critic/` |
| **`prompt-example-curator`** skill | Bands prompts bad/good/excellent and writes worked examples into the guide | `.claude/skills/prompt-example-curator/` |
| **`asset-suggester`** skill | Clusters recurring work across the journal into reusable-asset candidates | `.claude/skills/asset-suggester/` |
| **`asset-architect`** skill | Decides asset type + placement and scaffolds it (after your approval) | `.claude/skills/asset-architect/` |
| **`artifact-reviewer`** skill | Audits an existing asset against the same quality gate `asset-architect` builds to | `.claude/skills/artifact-reviewer/` |
| **`prompt-journal`** skill | Runs record → score → curate → suggest end to end | `.claude/skills/prompt-journal/` |

You never need to invoke a skill directly — each has a slash command in front of it. That's
the table below.

---

## Command reference

Every command is typed into the **Claude Code chat prompt**, not a shell (`render-guide.py`
is the one exception — it's a normal Python script). "Input" lists every argument/flag and
what it means; "Outcome" is exactly what gets written or printed, so you know what to expect
before you run it.

### `/configure`

**What it does** — one-step install/repair of the recorder hook. Detects your OS, patches
your Claude Code settings, self-tests the result. Safe to re-run any time.

| | |
|---|---|
| **Input** | Nothing required. Optional flags: `--project` (write the hook to *this repo's* `.claude/settings.json` instead of your global `~/.claude/settings.json` — scopes recording to just this repo); `--journal <path>` (`-JournalDir <path>` on Windows) — put logs somewhere other than the default sibling `../prompts` folder. |
| **Outcome** | A `UserPromptSubmit` hook registered (or repaired) pointing at this clone's `scripts/record-prompt.{sh,ps1}`; missing journal dir created; stale/duplicate hook entries removed; executable bit fixed on macOS/Linux. Prints one line per check: `[OK]` (already correct), `[FIXED]` (it corrected something for you), or `[ACTION]` (you need to do one manual step — it tells you exactly what). Ends with a self-test that confirms a prompt actually gets recorded. |
| **When to run it** | Once, right after cloning. Again any time prompts stop appearing in `../prompts/`. |

### `/analyse` (alias: `/prompt-review`)

**What it does** — the main pipeline: scores every prompt you've recorded and refreshes your
guide. Idempotent — re-running never double-counts a prompt.

| | |
|---|---|
| **Input** | Optional **selector** (pick at most one) — a file/dir path (e.g. `../prompts/master.txt`), `--project <name>`, or `--branch <name>`. **Omit it entirely to analyse your whole journal** (the default, and the normal way to run it). Optional `--user <name>` — whose store/guide to update; defaults to your OS username. |
| **Outcome** | For each log processed: a per-file review at `<outcomes>/reviews/<user>/<branch>.md` (that session's strengths/weaknesses + asset opportunities). Across the whole run: new lines appended to the append-only score store `<outcomes>/scores/<user>.jsonl`; your guide regenerated at `<outcomes>/guides/<user>.{json,md,pdf,docx}`; asset candidates refreshed at `<outcomes>/suggestions/<user>.json`. |
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
quality gate `/scaffold-asset` builds to. Read-only: it reports, it never edits.

| | |
|---|---|
| **Input** | Optional path to one asset file or a directory tree (default: `./.claude`, i.e. everything in the current repo). Optional `--focus <type\|rubric>` to narrow the audit to one asset type or one of the 7 quality rubrics (correctness/latency/cost/security/observability/scale/reliability). |
| **Outcome** | A severity-ranked findings report, a score, and a PASS/FAIL verdict, with a concrete suggested fix per finding. No files are modified — route any fix to `/scaffold-asset` or a human editor. |
| **When to run it** | Before trusting an asset (yours or someone else's) in a real workflow, or periodically to catch drift. |

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
| **Outcome** | Runs `scripts/selftest.sh` (deterministic recorder/configure/parser/renderer checks), then drives `prompt-critic`, `/analyse` (all selector forms), `asset-suggester`, `asset-architect` (draft-only), and `/catalog` over fixtures under a throwaway `_selftest` user. Prints a PASS/FAIL checklist, then tears down every test artifact and temp dir it created. **Never touches your real journal, scores, guide, suggestions, or settings.** |
| **When to run it** | After changing any script, skill, or fixture in this repo, to confirm nothing broke. |

### `scripts/render-guide.py` *(shell command, not a slash command)*

**What it does** — regenerates the human-readable views of your guide from its JSON source.
`/analyse` already calls this for you; run it by hand only if you edited the JSON directly or
want to re-render without a full `/analyse` pass.

| | |
|---|---|
| **Input** | Required positional arg: path to `<outcomes>/guides/<user>.json`. Optional flag to render just one format: `--md`, `--pdf`, or `--docx` (omit to render all three). Requires `reportlab` + `python-docx` (`pip install reportlab python-docx`). |
| **Outcome** | Writes `<user>.md`, `<user>.pdf`, and/or `<user>.docx` next to the JSON file in `<outcomes>/guides/`. |
| **When to run it** | Rarely — only for manual re-renders. |

```bash
python scripts/render-guide.py ../prompts-review-outcomes/guides/<user>.json          # all three: MD + PDF + DOCX
python scripts/render-guide.py ../prompts-review-outcomes/guides/<user>.json --pdf     # just one
```

---

## Setup, in detail

Only read this if `/configure` didn't just work, or you want to know what it's doing under
the hood.

### 1. Get the journal repo

Clone this repo somewhere stable. Everyone keeps **their own** journal — logs, scores, and
guide are per-person. The clone location does not matter; `/configure` derives everything
from wherever you put it.

```bash
git clone <this-repo-url> ~/prompt-journal      # macOS / Linux
```
```powershell
git clone <this-repo-url> "D:\code\prompt-improvement-framework"      # Windows
```

### 2. Run `/configure`

`/configure` is a **Claude Code slash command, not a shell command** — running it in
Terminal/PowerShell will just fail as "command not found". From the clone directory, start
a Claude Code session:

```bash
cd ~/prompt-journal   # or wherever you cloned it
claude
```

Then, **inside that Claude Code chat prompt**, type:

```
/configure
```

See the [command reference](#configure) above for exactly what it registers and prints.
It is **idempotent** — safe to re-run any time a prompt stops getting logged. You only need
to act when it prints an `[ACTION]` line (e.g. "install PowerShell 7", "install `jq` or
`python3`", "fix invalid JSON") — it tells you the exact step.

After it succeeds, **restart Claude Code / start a new session** so it reloads
`settings.json`.

<details>
<summary>Manual fallback (only if you can't run <code>/configure</code>)</summary>

Add a `UserPromptSubmit` hook to `~/.claude/settings.json` under `.hooks`, adjusting the
script path to your clone:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File \"<clone>/scripts/record-prompt.ps1\"", "timeout": 15 } ] }
    ]
  }
}
```
macOS / Linux: use `"bash \"<clone>/scripts/record-prompt.sh\""` instead, and run
`chmod +x scripts/record-prompt.sh`. The bash recorder needs `jq` or `python3` on `PATH`.
</details>

### 3. Verify

Send a throwaway prompt in any repo, then check that a `<branch>.txt` appeared in the sibling
`../prompts/` folder with a `===== [timestamp] branch=… =====` entry. (`/configure` already
self-tests this, so it should just work.) That's it — recording is now automatic.

> **Do not paste secrets into prompts.** Prompts are stored verbatim in plain-text logs.
> Treat the journal like any other source-controlled text: no credentials, tokens, or
> customer data. This is a security requirement, not a suggestion.

---

## Daily use

Just work. Every prompt you submit is appended to a log in the sibling `../prompts/` folder,
named after the current context, resolved in this order (slashes become hyphens in the filename):

1. **git branch** → `feature/PROJ-1234_x` becomes `feature-PROJ-1234_x.txt`;
2. **no branch → session name** (from `CLAUDE_SESSION_NAME`, or a named session) →
   `session/example-session` becomes `session-example-session.txt`;
3. **no session name → repo root folder** (or the working directory name) →
   `repo/my-app` becomes `repo-my-app.txt`.

Slash commands (`/build`, `/init`) are recorded too.

**Logs are append-only history — never edit them.** Their sloppiness is the data.

---

## What the rubric checks

`prompt-critic` — the skill `/analyse` calls to score each prompt — checks two layers (full
detail in `.claude/skills/prompt-critic/references/rubric.md`):

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
`.claude/skills/prompt-critic/references/conversational-chains.md`.

---

## Your guide

`../prompts-review-outcomes/guides/<user>.md` is your living, personalised output, written by
`/analyse`. It has:

- a **Snapshot** — prompts reviewed, band counts (excellent/good/bad), and trend vs. last
  time;
- **What excellent looks like** — your own strongest prompts, with why they work;
- **Good, one fix away** — near-misses with the single high-leverage fix;
- **Anti-patterns to kill** — your weakest prompts, each with a before→after rewrite;
- **Habits to build** and **Habits you already have**.

Every example is one of *your* real prompts, quoted verbatim with source and date. The
guide is regenerated by merging — it keeps what still teaches, adds new examples, and
retires stale ones. Format is fixed in
`.claude/skills/prompt-example-curator/references/guide-format.md`.

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
  in Anthropic's guidance — see `.claude/skills/asset-architect/references/sources.md`),
  localizes placement by reading the **target repo's `CLAUDE.md` + `.claude/rules/`**, drafts
  the asset to Anthropic's authoring standards, and **writes it only after you approve**.
- **`/review-asset`** audits an asset (new or old) against the same quality gate, any time you
  want a second opinion.

The guiding principle: *repetition tells you to capture a need; the signal tells you the type* —
a repeated **procedure** → skill, a **fact** → CLAUDE.md/rule, a **"whenever X" guarantee** →
hook (memory only steers; hooks enforce), an **isolated task** → subagent. `asset-architect`
complements your global `~/.claude/rules/sdlc-asset-authoring.md` and stays repo-local.

---

## Rolling it out to the team

- **Everyone records to their own files.** Each person runs `/configure` in their own clone;
  the default sibling `../prompts/` keeps their raw prompts out of the shared repo (point it
  elsewhere per person with `--journal <path>` or `PROMPT_JOURNAL_DIR`). Scores, guides, and
  suggestions are keyed by username under the outcomes dir (`<outcomes>/scores/<user>.jsonl`,
  `<outcomes>/guides/<user>.*`, `<outcomes>/suggestions/<user>.json`), so several people can share
  one framework clone without collisions — and each person can point `PROMPT_OUTCOMES_DIR` at their own.
- **Share the method, compare the guides.** The guides are the interesting artifact — swap
  them in a team channel, compare recurring gaps, and turn the sharpest before/after
  examples into shared prompting standards.
- **Keep the rubric stable.** Scores are only comparable over time if the rubric, band
  mapping, and guide format don't drift. Change them deliberately, in one place, and note
  it — see `CLAUDE.md`.
- **Calibrate before trusting scores as a gate.** If you wire `prompt-critic` into CI,
  hand-label ~50–100 prompts strong/weak first and check agreement before believing the
  number (`.claude/skills/prompt-critic/references/usage-and-integration.md`).

---

## Testing the framework

Run **`/test`** (see the [reference table](#test)) to verify everything end to end, in an
isolated sandbox that never touches your real journal, settings, scores, guide, or
suggestions. The underlying script harness alone is CI-friendly:

```bash
bash scripts/selftest.sh   # exits non-zero if any check fails
```

## Repo map

Data lives in two **sibling** folders beside the clone; the repo itself is machinery only.

```
D:/code/                                  (parent — holds the clone and its data siblings)
├── prompts/                          ← INPUT (sibling):  raw per-branch prompt logs (append-only)
│   └── <branch>.txt
├── prompts-review-outcomes/          ← OUTPUT (sibling): everything /analyse produces
│   ├── scores/<user>.jsonl               append-only score store (project, root, branch, score, band, …)
│   ├── guides/<user>.{json,md,pdf,docx}  structured guide (json = source of truth) + rendered views
│   ├── suggestions/<user>.json           reusable-asset candidates (machine-readable)
│   └── reviews/<user>/<branch>.md        per-file session reviews (strengths/weaknesses + asset opportunities)
└── prompt-improvement-framework/     ← THE REPO (machinery only; shareable)
    *_ANNOTATED.md                    hand/assisted prompt reviews (legacy format)
    scripts/configure.{ps1,sh}        one-step hook installer/repair (the /configure command)
    scripts/record-prompt.{ps1,sh}    recorder hook (writes the logs)
    scripts/render-guide.py           JSON guide -> Markdown + PDF + Word renderer
    scripts/selftest.sh               deterministic sandboxed self-test (first step of /test)
    scripts/validate-frontmatter.py   deterministic frontmatter gate (first step of /review-asset)
    tests/fixtures/                   sample logs + guide used by the /test play
    .claude/skills/prompt-critic/           scoring rubric + rewrite (+ optional asset_hint)
    .claude/skills/prompt-example-curator/  banding + guide curation
    .claude/skills/asset-suggester/         clusters recurring work into asset candidates
    .claude/skills/asset-architect/         multi-source grounding consumer: type + placement + scaffold
        references/artifact-anatomy.md      the skeleton of each emitted artifact (skill/agent/hook/…)
        references/grounding-sources.md     how it grounds from code, CLAUDE.md/rules, Confluence, prompts, docs
        references/quality-gate.md          the SHARED build+review checklist + rubric scorecard
    .claude/skills/artifact-reviewer/       read-only audit of existing assets against the quality gate
    .claude/skills/prompt-journal/          end-to-end pipeline
    .claude/skills/configure/               OS-detect + run the right configurator
    .claude/skills/catalog/                 capability catalog (commands/skills/agents)
    .claude/skills/test-framework/          the /test play (end-to-end framework test)
    .claude/commands/                       /analyse /prompt-review /scaffold-asset /review-asset /configure /catalog /test
    CLAUDE.md                         guidance for Claude working in this repo
```

## Troubleshooting

- **No log file appears** — just re-run `/configure`; it re-checks the hook path, removes any
  stale recorder entry, and self-tests the recorder (which exits silently on any error so it
  never blocks your prompt). Remember to start a new session so settings reload.
- **Everything lands in `no-branch.txt`** — you were not on a git branch (detached HEAD or
  a non-git directory). Expected.
- **`bash: python3: command not found`** — install `jq` or `python3`; the recorder needs
  one to parse the hook JSON.
