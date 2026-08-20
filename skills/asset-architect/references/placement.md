# Placement — where should the instruction live?

Two questions, in order: **which layer** (how broadly it applies) and **which mechanism**
(CLAUDE.md vs rule vs skill vs hook vs subagent prompt).

## The memory / instruction hierarchy (broad → specific)

| Scope | Location | Use for |
|---|---|---|
| **Managed policy** (org-wide, cannot be excluded) | OS-managed path / `managed-settings.json` `claudeMd` | Security / compliance mandates |
| **User** (all your projects) | `~/.claude/CLAUDE.md` (+ `~/.claude/rules/*.md`) | Personal conventions, personal governance |
| **Project / repo** (team-shared, committed) | `./CLAUDE.md` or `./.claude/CLAUDE.md` (+ `.claude/rules/*.md`) | Repo conventions, service rules |
| **Local** (this project, not committed) | `./CLAUDE.local.md` (gitignored) | Personal, machine-specific |

Claude walks **up** the tree from cwd and **concatenates all discovered files** (root→cwd,
`CLAUDE.local.md` after `CLAUDE.md`). On conflict, more specific + managed take precedence —
but CLAUDE.md is *additive context*, i.e. Claude's judgment, not hard enforcement. Assets that
override **by name** differ: skills (managed > user > project), subagents (managed > CLI >
project > user > plugin), hooks **all merge and fire**.

## Which mechanism (Anthropic's own comparison)

- **CLAUDE.md** — "always do X" facts, build commands, structure. Loads **every session in
  full** → costs context every request. Keep &lt; 200 lines.
- **`.claude/rules/*.md`** — same as CLAUDE.md but modular and optionally **path-scoped**
  (`paths:` frontmatter) so it loads only when matching files are open. Use it to keep
  CLAUDE.md small and to hold NEVER/ALWAYS governance.
- **Skill** — reference material / workflows needed **sometimes**; loads on demand. Move a
  CLAUDE.md section here once it becomes a procedure rather than a fact.
- **Hook** — the **guarantee** layer for "must happen at a fixed point" (before commit, after
  edit). Enforced by the harness, not the model.
- **Subagent system prompt** — instructions that should govern a single **isolated delegate**,
  not the whole session.

### The always-on-vs-on-demand test
Put it in **memory (CLAUDE.md/rule)** if *Claude should always know it* (a concise fact needed
every session). Put it in a **skill** if it's *reference/procedure needed only sometimes*. If
CLAUDE.md is growing past ~200 lines, that is the signal to move content into skills or
path-scoped rules. If it must be *guaranteed*, it's a **hook**, wherever the human-readable
rationale also lives.

## Localize to the target repo (required step)

Before choosing a concrete path, **read the target repo's `CLAUDE.md` and `.claude/rules/`**
and follow what you find:
1. **Layering** — does the repo already define layers/precedence (e.g. system → project → repo
   → service rules)? Slot the instruction into the correct tier.
2. **Conventions** — naming (kebab-case), required file headers (e.g. `# ai-gen — …`, but
   never in `.json`), size limits, and **registration points** (an `index.md`, a README table,
   a command list). Match them exactly.
3. **Scope discipline** — repo-specific → the repo; reusable across people *and* services →
   only *suggest* a global/org home, don't write there unprompted (`org-contribution-scope.md`).
4. **Governance deference** — where the repo has a governing rule (e.g.
   `sdlc-asset-authoring.md` Rule P phase categorization + layer separation), apply it rather
   than inventing a placement.

Output of this step: the exact destination path + why, ready for the Step 4 approval gate.
