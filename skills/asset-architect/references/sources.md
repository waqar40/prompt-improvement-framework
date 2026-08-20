# Authoring rules per type + sources

Distilled from official Anthropic / Claude Code documentation (verified 2026-08-14). Apply
these when drafting in Step 4; they sit on top of the target repo's own conventions.

## Per-type authoring rules

### Skill (`SKILL.md`)
- Frontmatter: **required `name` + `description` only.** `name` ≤ 64 chars, lowercase /
  digits / hyphens, matches the folder, no reserved words ("claude"/"anthropic").
  `description` ≤ 1024 chars. Optional Claude Code keys: `allowed-tools`,
  `disable-model-invocation`, `context: fork`. **`argument-hint` is NOT valid in SKILL.md**
  (it errors — that key belongs to slash commands).
- **Description is the trigger** — the one field Claude matches to load the skill. Third
  person; state **what it does AND when to use it**; include concrete key terms / file types.
- **Progressive disclosure:** SKILL.md is a table of contents. **Body &lt; 500 lines**; move
  detail to `references/` (one level deep; add a ToC to reference files &gt; 100 lines).
- Only add what Claude doesn't already know; match verbosity to task fragility; build ~3 evals.

### Subagent (`.claude/agents/*.md`)
- Frontmatter: `name`, `description`, `tools` (allowlist) or `disallowedTools` (denylist),
  optional `model`. **Single responsibility**; focused system prompt.
- **Tool-scope it** (e.g. a reviewer gets `Read, Grep, Glob` and no `Write`/`Edit`).
- **Description drives auto-invocation** — name specific tasks/file-types/triggers; too-general
  descriptions are the #1 failure. Add "Use proactively after …" to encourage delegation.

### Hook (`settings.json`)
- Exact events include `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `SessionStart`,
  `SessionEnd`, `PreCompact`, … (~30). Configure in `~/.claude/settings.json` (personal),
  `.claude/settings.json` (project), or `.claude/settings.local.json` (gitignored).
- **Exit codes:** `0` = ok (for `UserPromptSubmit`/`SessionStart`, stdout is added to context);
  `2` = **blocking** (blocks the tool / erases the prompt; stderr is the reason); **any other
  code, including 1, does NOT block.** For structured control, exit 0 + JSON `permissionDecision`.
- Use hooks for side effects that shouldn't need Claude to think (format-on-save, logging,
  guardrails). Block **by design** (exit 2), never **unintentionally** (don't crash / rely on 1).

### Slash command (`.claude/commands/*.md`)
- **Thin wrapper**: frontmatter + a body that reads a skill and forwards args. Keep it small.
- Frontmatter: `description` (so it's discoverable), `argument-hint`, `allowed-tools`
  (scope narrowly), `model`, `disable-model-invocation`.
- Args: `$ARGUMENTS` = full string; `$1`/`$ARGUMENTS[N]` = positional. `` !`cmd` `` injects
  command output; `@path` inlines a file.

### Memory rule (`CLAUDE.md` / `.claude/rules/*.md`)
- Facts/conventions only; keep CLAUDE.md &lt; 200 lines. Use `.claude/rules/*.md` with `paths:`
  for path-scoped or NEVER/ALWAYS governance. Remember: this **steers**, it does not enforce.

### Script (`scripts/…`)
- Prefer a pre-made script over asking Claude to regenerate equivalent code when the op is
  fragile/deterministic — reliable, token-cheap, consistent. Its output (not its code) returns.

## Sources

Official docs (`platform.claude.com/docs`, `code.claude.com/docs`; successors to
`docs.anthropic.com`/`docs.claude.com`):

- **Agent Skills — Overview** — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview — what a skill is; progressive disclosure; `name`/`description` frontmatter rules; skill paths.
- **Skill authoring best practices** — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices — description quality, 500-line body limit, one-level references, evals.
- **Extend Claude Code (features overview)** — https://code.claude.com/docs/en/features-overview — the master decision guide: "match features to your goal" + "build your setup over time" trigger tables; put guardrails in hooks.
- **Memory / CLAUDE.md** — https://code.claude.com/docs/en/memory — four memory scopes + load order; 200-line target; `.claude/rules/` + `paths:`; "use a PreToolUse hook to enforce."
- **Subagents** — https://code.claude.com/docs/en/sub-agents — frontmatter, isolated context, tool scoping, description-driven delegation.
- **Hooks reference** — https://code.claude.com/docs/en/hooks — event names; exit-code semantics (0/2/other; exit-1-doesn't-block); settings locations.
- **Slash commands** — https://code.claude.com/docs/en/slash-commands — locations, frontmatter, `$ARGUMENTS`/`$N`; commands merged into skills.
- **Use Skills in Claude Code** — https://code.claude.com/docs/en/skills — skill-wins-over-command precedence; `disable-model-invocation`; `context: fork`.

Community / GitHub:
- **anthropics/skills** — https://github.com/anthropics/skills — Agent Skills open standard, examples, `package_skill.py`.
- **anthropics/claude-code** — https://github.com/anthropics/claude-code — official repo behind the docs.

Prior art on this machine (defer to, don't duplicate): `~/.claude/rules/sdlc-asset-authoring.md`
(phase categorization + layer separation + size limits), `~/.claude/rules/org-contribution-scope.md`
(repo-local vs org), `~/.claude/rules/code-quality.md` (don't over-build).
