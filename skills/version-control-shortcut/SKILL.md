---
name: version-control-shortcut
description: Use when the user gives a vague git instruction like "commit this", "push it", or "version-control it" instead of naming the exact action, file scope, or message. Resolves the intended git operation from `git status`/`git diff` and the conversation, guards against staging this repo's gitignored prompt-data paths, and defers entirely to the existing git safety protocol (no force-push, no amend-by-default, review before pushing) rather than re-deriving it. Triggers include "commit this", "version-control it", "push it", "save my changes to git".
---

# Version Control Shortcut

Resolve a vague git instruction — "commit this", "push it", "version-control it" — into the one
concrete action it actually means, using this repo's real git history and `.gitignore` as the
ground truth. This does not replace the existing git safety protocol (never force-push, create
new commits rather than amending, ask before pushing, review staged files, HEREDOC commit
messages) — it only resolves *which* action and *what scope* a vague prompt meant; every command
it runs still obeys that protocol.

## Step 1 — Inspect before guessing
Run `git status` and `git diff` (read-only) to see what's actually staged/unstaged/changed.
Never assume what "this"/"it" refers to — resolve it from the real diff, or ask if genuinely
ambiguous (e.g. unrelated changes across multiple unrelated files with no single clear "this").

## Step 2 — Guard the repo's known-sensitive paths
Before staging anything, feed every changed/untracked path from Step 1 through
`git check-ignore -v --stdin` in one call (exit 1 = nothing matched = clean) — never a plain
substring match against the directory names (`/prompts/`, `/logs/`, `/prompts-review-outcomes/`,
`/scores/`, `/guides/`, `/suggestions/`, `/reviews/` are root-anchored in `.gitignore`, so e.g.
`tests/fixtures/logs/...` is a false positive for `/logs/` on a naive substring check —
`git check-ignore` applies the real, anchored match and is the only authoritative source; prefer
the single `--stdin` call over a per-path loop, which can hit shell/PATH quirks in some
environments). If a path matches **and** is untracked (`git ls-files <path>` empty) — e.g. a
relocated `PROMPT_JOURNAL_DIR`/`PROMPT_OUTCOMES_DIR` pointed inside the repo by mistake — **stop
and flag it**, never silently `git add` it. An already-tracked file (checked-in fixtures, docs
that happen to mention one of those words) is never a hit, no matter what its path contains.

## Step 3 — Resolve the action and state the plan
Map the instruction onto one concrete action:
- "commit this" → stage the specific files the diff shows are relevant (never a blind `git add
  -A`/`.`), with a message following this repo's own convention (`type: imperative description`,
  e.g. `feat:`/`fix:`/`docs:`/`chore:` — most but not all commits here use one; match the pattern
  when the change fits one of those types).
- "push it" / "version-control it to the shared repo" → commit first if anything is uncommitted
  (Step 3 still applies to that commit), then push the current branch.
Before running anything, state the plan in one line: files staged, the exact message, and
whether a push follows.

## Step 4 — Run it, following the existing protocol unconditionally
Run the resolved `git add`/`git commit`/`git push` commands exactly as planned. This skill
**never** overrides the standing git safety protocol: no `--force`, no `git reset --hard`, no
`git commit --amend` unless the user explicitly asked for an amend, no skipped hooks, and commit
messages still end with the required `Co-Authored-By` line. If the resolved action needs any of
those, stop and ask instead of running it.

## Step 5 — Report what ran
State the exact command(s) run and their result (the new commit SHA, or confirmation the push
succeeded) — never a vague "done".

## Constraints
- NEVER run `git push --force`, `git reset --hard`, `git clean -f*`, `git branch -D`, or `git
  commit --amend` unless the user explicitly asked for that specific action — this mirrors the
  standing git safety protocol, it does not loosen it.
- NEVER stage a path under this repo's gitignored data directories, even via a blind `git add
  -A` — Step 2's guard is mandatory, not optional.
- NEVER guess which files "this"/"it" refers to when the diff shows unrelated changes across
  multiple files — ask which one was meant.
- ALWAYS state the plan (Step 3) before running a command that commits or pushes.
- ALWAYS report the exact command and result (Step 5).
