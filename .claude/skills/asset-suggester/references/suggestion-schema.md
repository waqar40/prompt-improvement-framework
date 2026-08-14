# `<outcomes>/suggestions/<user>.json` — schema & merge rules

One file per user, stored under the **outcomes dir** (`PROMPT_OUTCOMES_DIR`, default the sibling
`../prompts-review-outcomes`), never inside the repo. It is the backlog that `asset-architect`
(via `/scaffold-asset`) reads to author assets.

## Schema

Machine-readable by design: `asset-architect` consumes this to **trace the target repo on disk**
(or via git) and build a grounded artifact. Populate `target_project` and `grounding` from the
`project=`/`root=` headers the recorder now writes.

```json
{
  "user": "waqar.aziz",
  "updated": "<YYYY-MM-DD>",
  "candidates": [
    {
      "id": "<stable-kebab-slug>",           // derived from canonical intent; stable across runs
      "type": "skill | agent | hook | command | rule | script",
      "title": "<short human label>",
      "rationale": "<why this should be an asset; note any alternative type>",
      "signal": "<the signal that set the type: repeated-procedure | guarantee | isolated-task | durable-fact | shortcut | fragile-code>",
      "frequency": 3,                          // occurrences across the whole store
      "evidence": [
        {"prompt_excerpt": "<verbatim, trimmed>", "source": "<log file>", "project": "<project or 'unknown'>", "branch": "<branch>", "date": "<YYYY-MM-DD>"}
      ],
      "target_project": {                      // WHERE the asset is for — lets asset-architect locate the repo
        "name": "<project= header value, or 'unknown'>",
        "root_path": "<root= header value: the repo's absolute path on this machine, or ''>",
        "git_remote": "<origin URL if trivially known; else '' (asset-architect resolves from root_path)>",
        "branches": ["<branches this need appeared on>"]
      },
      "grounding": {                           // WHAT the artifact builder should read (multi-source)
        "claude_md": "<root_path>/CLAUDE.md if it exists, else ''",
        "rules_dir": "<root_path>/.claude/rules if it exists, else ''",
        "code_globs": ["<globs/paths in the repo relevant to the need, best-effort from the prompts>"],
        "confluence_pages": ["<page URL / id / title the prompts referenced, else empty>"],
        "documents": ["<path to a PRD/spec/guide doc the prompts referenced, else empty>"],
        "prompt_evidence": ["<source-log/branch the need came from — the raw prompts to mine for triggers>"]
      },
      "proposed_trigger": "<trigger phrase / slash name, for skill|command; else empty>",
      "target_location": "<where the asset FILE should live, e.g. <root_path>/.claude/skills/<name>/ or ~/.claude/rules/<name>.md>",
      "confidence": "high | medium | low",
      "status": "proposed"                     // proposed -> accepted -> authored | dismissed
    }
  ]
}
```

### Populating the metadata (no fabrication)

- `target_project.name` / `root_path` come straight from the log headers (`project=` / `root=`).
  When several projects share one candidate, pick the **most frequent** project as primary and
  list the others' branches under `branches`; note the split in `rationale`.
- Leave `root_path`/`git_remote` **empty** for old logs that lack the headers — never guess a path.
- `grounding.code_globs` is a best-effort hint from what the prompts touched (e.g. `src/billing/**`);
  it steers `asset-architect`'s reading, which still verifies against the real repo.
- `grounding.confluence_pages` / `documents` come from URLs/paths the prompts actually referenced
  (Confluence links, PRD/spec/guide paths) — capture them verbatim, don't invent. `prompt_evidence`
  points at the source logs so the builder can mine the user's real wording for triggers.

## Merge & idempotency rules

- **Match on `id`** (stable slug of the canonical intent). If a candidate with that `id`
  exists, **update** `frequency`, append new `evidence` (dedupe by prompt_excerpt+date), and
  refresh `confidence` — do **not** create a duplicate.
- **Never overwrite a human-touched candidate.** Only candidates with `status: "proposed"`
  may be auto-updated. Leave `accepted` / `authored` / `dismissed` candidates as-is (you may
  still append evidence, but never change their `type`, `status`, or `target_location`).
- **Never remove** a candidate you didn't add this run; suggestions are a growing backlog.
- Sort `candidates` by `confidence` (high→low) then `frequency` (desc) for readability.
- `status` lifecycle: `asset-suggester` writes `proposed`; a human/`asset-architect` moves it
  to `accepted` (chosen to build), `authored` (built), or `dismissed` (won't build).
