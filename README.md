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
> installed and a `claude` session open in the clone before Part A, step 2.

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

Six moving parts, all in this repo:

| Piece | What it is | Where |
|---|---|---|
| **Recorder hook** | Appends each prompt to a per-branch log file in the sibling `../prompts/` | `scripts/record-prompt.ps1` / `.sh` |
| **`prompt-critic`** skill | Scores a prompt (D1–D10 design + E1–E4 evaluability), localizes gaps, rewrites it | `.claude/skills/prompt-critic/` |
| **`prompt-example-curator`** skill | Bands prompts bad/good/excellent and writes worked examples (rubric + transformation tables) into the guide | `.claude/skills/prompt-example-curator/` |
| **`asset-suggester`** skill | Clusters recurring work across the journal into reusable-asset candidates | `.claude/skills/asset-suggester/` |
| **`asset-architect`** skill + **`/scaffold-asset`** | Decides asset type + placement and scaffolds it (after approval) | `.claude/skills/asset-architect/`, `.claude/commands/scaffold-asset.md` |
| **`prompt-journal`** skill + **`/analyse`** command | Runs record → score → curate → suggest end to end over a log or the `../prompts/` dir | `.claude/skills/prompt-journal/`, `.claude/commands/analyse.md` |

---

## Part A — One-time setup (each teammate)

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

### 2. Run `/configure` (one step)

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

That is the whole setup. `/configure` detects your OS and runs the matching
`scripts/configure.*`, which:

- registers a `UserPromptSubmit` hook in your **global** `~/.claude/settings.json` pointing
  at *this clone's* recorder, so **every prompt in every repo** is captured;
- lands logs in a **sibling `prompts/` folder beside the clone** (`<clone>/../prompts`) — kept
  out of the repo so your prompts are never committed. No `PROMPT_JOURNAL_DIR` needed;
- auto-fixes the common issues (missing journal dir, a stale/duplicate recorder hook, a missing
  `settings.json`, the `chmod +x` bit on the bash recorder, `pwsh` vs `powershell`);
- **self-tests** the recorder and prints a summary of `[OK]` / `[FIXED]` / `[ACTION]` lines.

It is **idempotent** — safe to re-run any time a prompt stops getting logged. You only need
to act when it prints an `[ACTION]` line (e.g. "install PowerShell 7", "install `jq` or
`python3`", "fix invalid JSON") — it tells you the exact step. Options: `--project` scopes the
hook to just this repo; `--journal <path>` (`-JournalDir <path>` on Windows) keeps the journal
somewhere other than the default sibling folder.

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

## Part B — Daily use

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

## Part C — Analyze and rate your prompts

**By default `/analyse` reviews your whole journal** — every log across every project and
branch. Narrow it only when you want to: pass a file/dir path, `--project <name>`, or
`--branch <name>`.

```
/analyse                                   --user waqar.aziz   # everything (default)
/analyse --project core-service            --user waqar.aziz   # one project
/analyse --branch feature/PROJ-1234_x      --user waqar.aziz   # one branch
/analyse ../prompts/master.txt             --user waqar.aziz   # one file
```
(`/prompt-review` still works as an alias.) Or just ask Claude in this repo: *"review all my
prompts and update my guide."* Either way the `prompt-journal` skill:

1. Splits each log into sessions (entries under one branch, in time order = one chain).
2. Scores each prompt with **`prompt-critic`**, passing earlier turns as `session_context`.
3. Writes a **per-file review** to `../prompts-review-outcomes/reviews/<user>/<branch>.md` — that
   related session's strengths, weaknesses, and asset opportunities (worth turning into a skill/agent/hook).
4. Appends results to `../prompts-review-outcomes/scores/<user>.jsonl` (with the log's `project`/`root`).
5. Compiles the **overall** guide `../prompts-review-outcomes/guides/<user>.{json,md,pdf,docx}` from
   the *whole store* with **`prompt-example-curator`** — grounded in your real history.
6. Clusters recurring work into machine-readable `../prompts-review-outcomes/suggestions/<user>.json`
   with **`asset-suggester`**.

(All outputs sit under the sibling outcomes dir — `PROMPT_OUTCOMES_DIR`, default `../prompts-review-outcomes`.)

### What the rubric checks

`prompt-critic` scores two layers (full detail in
`.claude/skills/prompt-critic/references/rubric.md`):

- **Layer 1 — Design:** clarity & explicit action verb (D1), specificity & constraints
  (D2), output format (D3), context/motivation (D4), grounding (D5), examples (D6),
  positive framing (D7), uncertainty handling (D8), decomposition fit (D9), structural
  economy — no over-engineering (D10).
- **Layer 2 — Evaluability:** is success defined (E1), measurable (E2), multidimensional
  (E3), and are failure modes anticipated (E4).

It produces a JSON contract (score 0–100, verdict `STRONG/ADEQUATE/WEAK/POOR/BLOCKED`, a
per-dimension finding with evidence, a rewritten prompt, and suggested eval criteria) then
a short Markdown summary.

### Short prompts and chains are handled fairly

Most real prompts are terse follow-up turns that lean on session context (`"push it"`,
`"are we good to merge?"`). The critic scores these as **chain steps**: it judges them
against what the session already resolved and **never penalizes brevity** — a one-word
`"yes"` can be an excellent turn. It only flags a reference the session genuinely left
ambiguous, an undefined verb, or an untestable success word. See
`.claude/skills/prompt-critic/references/conversational-chains.md`.

---

## Part D — Your guide

`../prompts-review-outcomes/guides/<user>.md` is your living, personalised output. It has:

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

**Human-friendly formats.** The guide has one structured source, `../prompts-review-outcomes/guides/<user>.json`,
and three rendered views — **Markdown, PDF, and Word** — all produced from it. Each
reviewed prompt renders a **rubric scorecard** (every D1–D10 / E1–E4 dimension marked
Met / Partial / Missing / n-a, with evidence) and a **transformation table** (each gap →
a concrete rewrite + the principle it teaches), so it is explicit on which grounds the
prompt was reviewed and which best practices it missed. Regenerate the views any time:

```bash
python scripts/render-guide.py ../prompts-review-outcomes/guides/<user>.json          # all three: MD + PDF + DOCX
python scripts/render-guide.py ../prompts-review-outcomes/guides/<user>.json --pdf     # just one
```
(Uses `reportlab` + `python-docx` — no external tools. `pip install reportlab python-docx`
if missing.)

---

## Part E — Turn recurring work into reusable assets

Reviewing prompts also surfaces **what you keep doing** — and repeated work is a signal to
build a reusable Claude Code asset. `/analyse` records those signals; two pieces act on them:

- **`asset-suggester`** clusters recurring intents/tools/tasks across your whole journal (plus
  any per-prompt `asset_hint` from `prompt-critic`) into candidates in `suggestions/<user>.json`
  — each typed provisionally as a **skill / subagent / hook / slash command / rule / script**,
  with the evidence (your real repeated prompts), a proposed trigger, and where it should live.
- **`asset-architect`** (via **`/scaffold-asset <id>`**) makes the authoritative call: it
  applies a decision matrix (grounded in Anthropic's guidance — see
  `.claude/skills/asset-architect/references/sources.md`), localizes placement by reading the
  **target repo's `CLAUDE.md` + `.claude/rules/`**, drafts the asset to Anthropic's authoring
  standards, and **writes it only after you approve**.

The guiding principle: *repetition tells you to capture a need; the signal tells you the type* —
a repeated **procedure** → skill, a **fact** → CLAUDE.md/rule, a **"whenever X" guarantee** →
hook (memory only steers; hooks enforce), an **isolated task** → subagent. `asset-architect`
complements your global `~/.claude/rules/sdlc-asset-authoring.md` and stays repo-local.

---

## Part F — Rolling it out to the team

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

Run **`/test`** (the test play) to verify everything end to end. It:

1. runs `bash scripts/selftest.sh` — a deterministic, sandboxed harness that asserts the
   recorder header + branch/session/repo fallbacks, `configure` idempotency / stale-removal /
   self-test / `--journal`, the header parser, and the guide renderer;
2. then drives the LLM-side pieces over `tests/fixtures/` under a throwaway `_selftest` user —
   `prompt-critic`, `/analyse` (all + `--project` + `--branch` + single file), `asset-suggester`,
   `asset-architect` (draft-only, approval gate), and `/catalog` — checking each outcome;
3. tears down every `_selftest` artifact and temp dir.

It never touches your real journal, settings, scores, guide, or suggestions. The script harness
alone is CI-friendly: `bash scripts/selftest.sh` exits non-zero if any check fails.

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
