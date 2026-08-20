# Verification Harness — the schema behind gate Section F

Section F of `quality-gate.md` requires every artifact to "ship its own check." This file gives
that requirement one concrete, runnable shape instead of leaving each artifact to invent its own —
comparable in spirit to a Waza `wazaEval.yaml` (tasks + graders + weighted metrics), but plain
JSON, no external binary, no network call, and runnable by Claude itself or `pytest`/`bash`/CI.

Not every type needs the full shape (a script's self-test can just be `exit 0`/`1`) — use the
**minimum row** from the table below, and only reach for `evals/evals.json` when the artifact's
correctness is genuinely judgment-shaped (a skill/agent whose output quality isn't a single exit
code).

## Minimum verification per type

| Type | Minimum verification | When to use the full `evals.json` schema below |
|---|---|---|
| Skill | at least 1 golden-path case + 1 adversarial/edge case | whenever the skill's output is graded content (a review, a rewrite, a report), not just "ran without error" |
| Subagent | the output contract itself, checked against a real invocation | when a downstream gate/script parses the agent's output — add a `json_schema` grader |
| Hook | a sample-payload → exit-code assertion (see `scripts/selftest.sh` for the pattern) | rarely needed — hooks are deterministic, one `program` grader usually suffices |
| Command | a dry-run / `--help` path that doesn't mutate anything | rarely — commands are thin wrappers; verify the skill they forward to instead |
| Rule | an adherence check: does the NEVER/ALWAYS hold across 2-3 realistic prompts | when the rule is safety-critical (deletion, destructive-op gating) |
| Script | non-zero exit on a known-bad input, zero on a known-good one | when the script has more than one code path |

## `evals/evals.json` schema

```json
{
  "skill": "<skill-or-agent-name>",
  "cases": [
    {
      "id": "<short-id>",
      "kind": "golden | adversarial | regression",
      "input": { "...": "the prompt/inputs given to the artifact" },
      "graders": [
        { "type": "text", "must_contain": ["exact phrase"], "must_not_contain": ["banned phrase"] },
        { "type": "file", "path": "expected/output/path", "exists": true },
        { "type": "json_schema", "against": "references/output-contract.md#schema-name" },
        { "type": "exit_code", "expect": 0 },
        { "type": "prompt", "judge": "Does the output do X without doing Y? Answer PASS or FAIL with one reason." }
      ]
    }
  ],
  "metrics": [
    { "name": "correctness", "weight": 0.7, "threshold": 1.0 },
    { "name": "no_fabrication", "weight": 0.3, "threshold": 1.0 }
  ]
}
```

## Grader types (deliberately small — extend only when a real case needs it)

| Grader | Checks | Example use |
|---|---|---|
| `text` | substring/regex presence or absence in the output | "the refined prompt must not contain the word 'seamlessly'" |
| `file` | a file exists / doesn't exist / matches a diff | "the reviewer wrote no file" (read-only proof) |
| `json_schema` | the output's leading JSON matches a documented schema | `prompt-critic`'s `output-contract.md`, this repo's findings contract |
| `exit_code` | a script/hook returns the expected code for a payload | hook self-tests, `validate-frontmatter.py` |
| `prompt` | a second, independent LLM call judges a qualitative property | "is this rewrite shorter and does it fix the blocking gap?" — use sparingly, it's the least deterministic grader |

## Running it

No dedicated binary — either:
1. **By hand / in review**: walk each case, run the artifact, apply the graders, record pass/fail.
2. **In `/test`**: `test-framework` drives real fixture inputs through the artifact and asserts the
   graders' conditions in prose steps (see `skills/test-framework/SKILL.md` for the pattern this
   repo already uses — it *is* an `evals.json`-shaped harness, just written as workflow steps
   instead of JSON, because every artifact here is judgment-shaped).
3. **In CI**: a thin script that loads `evals.json`, invokes `claude -p` per case, and applies the
   `text`/`file`/`exit_code`/`json_schema` graders programmatically; route `prompt` graders to a
   second `claude -p` call. Not required for this repo today — document as a follow-up when an
   artifact's stakes justify the CI investment (see `quality-gate.md` Section F).

## What this buys over "ships a verification" (prose only)

- **Comparable across artifacts** — every skill's evals answer the same three questions (what
  input, what grader, what threshold) instead of a bespoke paragraph each reviewer re-interprets.
- **Diffable over time** — `evals.json` is a file; a regression shows up as a graders' output
  changing between runs, not as a reviewer's fading memory of "it used to handle that case."
- **Cheap to add** — a 5-line JSON case is less writing than the prose it replaces, and
  `artifact-reviewer` can check the file's *presence and shape* deterministically (Section F is
  currently judgment-only; once `evals/evals.json` exists, checking it's non-empty and each case
  has ≥1 grader is a `grep`/`json.load`, not a read of the whole artifact).
