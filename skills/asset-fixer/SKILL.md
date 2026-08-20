---
name: asset-fixer
description: Use to APPLY the mechanical, fully-specified fixes from an artifact-reviewer findings report to an existing Claude Code asset (skill/agent/hook/command/rule/script) — never to redesign or author new content. Takes the reviewer's findings (or re-runs the review itself), applies only fixes a reviewer already spelled out completely (dangling reference removed, invalid frontmatter key dropped, stale table row deleted), and skips + routes onward anything that needs judgment or new prose. Mirrors the read-only artifact-reviewer / write-capable asset-fixer split. Triggers include "fix this skill", "apply the review findings", "fix-asset", "clean up the mechanical issues artifact-reviewer found", and the /fix-asset command.
allowed-tools: Read, Edit, Grep, Glob, Bash
---

# Asset Fixer

Apply **only** the fixes an `artifact-reviewer` pass already fully specified. This is the write
half of the review/fix split (`artifact-reviewer` is read-only by design — separation of powers).
One job: turn a findings report into edits, verbatim, with zero invention. Anything that needs
authored content or a structural call is **not this skill's job** — route it to `/scaffold-asset`.

## References
| File | Contents |
|---|---|
| `../asset-architect/references/quality-gate.md` | The severities (blocking/major/minor) and gate this skill's fixes are scored against. |
| `../asset-architect/references/semantic-consistency.md` | Section G — most mechanical fixes (G6 dangling reference, G1/G2 phrasing) are defined here. |

## Inputs
- `target`: the asset file (or dir) to fix.
- `findings` (optional): an `artifact-reviewer` findings report (JSON or its markdown form). **If
  absent, run `artifact-reviewer` on `target` first** to get one — never fix from your own read.

## Workflow

### Step 1 — Get a findings report
Use the supplied `findings`, or invoke `artifact-reviewer` on `target` if none was given. Discard
any finding not labeled `mechanical` (Step 3 of `artifact-reviewer`) — this skill never acts on a
finding that needs authored content or redesign.

### Step 2 — Classify each mechanical finding as auto-fixable or not
A finding is auto-fixable only if the fix requires **deleting or correcting something already
fully specified** — no new sentence needs to be written. Auto-fixable: an invalid frontmatter key
(`argument-hint` in a SKILL.md), a `references/` table row pointing at a file that doesn't exist
(G6 dangling reference — delete the row), a stale path after a rename the finding already names,
a duplicated/contradictory line where the finding names which one is stale. **Not auto-fixable**
(skip, route onward): a missing verification, a vague description, a missing Constraints section,
persona drift, cognitive-load restructuring — all of these need someone to write something.

### Step 3 — Apply, one finding at a time
For each auto-fixable finding: `Read` the exact `file:line` the finding cites, confirm the content
still matches what the finding described (files drift — if it doesn't match, skip and report why),
then make the **smallest edit that resolves it** — delete the offending line/row, correct the exact
token named. Never touch a line the findings report didn't cite. Never restructure, rename, or
rewrite prose beyond what the finding specifies.

### Step 4 — Re-validate
Run `python scripts/validate-frontmatter.py <target>` and re-check the specific findings you
touched (re-read the cited lines) — confirm the fix actually resolves them and introduced no new
frontmatter error. Do **not** re-run the full judgment review (that's `artifact-reviewer`'s job).

### Step 5 — Report
List, per finding: `file:line — fix applied` or `file:line — SKIPPED (not auto-fixable: <why>)` or
`file:line — SKIPPED (content changed since review)`. End with a count and a pointer: "N findings
still need `/scaffold-asset` or a human" for anything skipped.

## Constraints
- NEVER apply a finding that isn't labeled `mechanical` by the reviewer, and never invent a finding
  of your own — this skill fixes what was found, it does not also review.
- NEVER write new prose, new sections, new files, or a new verification — that's authoring, route
  to `/scaffold-asset`.
- NEVER delete a file; only `Edit` existing ones, and only the lines a finding named.
- ALWAYS re-read the cited line before editing it — a stale findings report (file changed since
  review) means skip, not guess.
- ALWAYS run `validate-frontmatter.py` after touching any frontmatter.
- If in doubt whether a fix counts as "authoring", treat it as not-auto-fixable and skip it —
  false negatives (an unfixed mechanical issue) are cheap; false positives (an invented rewrite)
  are not.
- Verification: given `tests/fixtures/assets/bad-skill/` and its known reviewer findings, this
  skill must fix exactly the 2 mechanical findings (invalid `argument-hint` key, dangling
  `references/` row) and skip+report the 2 non-mechanical ones (vague description, missing
  Constraints) unchanged.
