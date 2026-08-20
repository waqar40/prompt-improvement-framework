# Decision matrix — which asset type?

Claude Code extensions sit on a spectrum (Anthropic, *Extend Claude Code*):
**always-on context (CLAUDE.md / rules) → on-demand knowledge & workflows (skills, commands)
→ isolated execution (subagents) → deterministic automation (hooks) → external systems (MCP)**,
with **scripts** as the deterministic code a skill or hook runs.

## The core rule

> **Repetition tells you to *capture* a need; the *signal* tells you *what type*.**

"If something is done more than once, make it a skill" is a useful rounding but wrong as
stated. Anthropic's own trigger table splits "done repeatedly" by *what* repeats, and the
threshold it names is roughly the **third manual repetition** — and only for *procedures*
does that land on "skill".

## Signal → type

| Strongest signal | Asset type | Why |
|---|---|---|
| A repeated **multi-step procedure / playbook**, or a reference you keep restating; needed only **sometimes** | **Skill** (`.claude/skills/<name>/SKILL.md`) | Loads on demand via progressive disclosure; the most flexible extension. |
| A durable **fact / convention / NEVER-ALWAYS** Claude must hold **every session** | **Memory rule** (`CLAUDE.md` or `.claude/rules/*.md`) | Always-on context. Keep CLAUDE.md &lt; 200 lines; path-scope big rules. |
| Something that must happen **every time, without asking** ("whenever X, do/deny Y") | **Hook** (`settings.json` event) | The **enforcement** layer — fires deterministically regardless of what Claude decides. |
| A **delegated, isolated multi-step task** that would flood the main context, or needs its own tool set/model | **Subagent** (`.claude/agents/*.md`) | Runs in its own context window; returns only a summary. |
| A **prompt you keep typing to start a task** (explicit, human-triggered; may have side effects) | **Slash command** (`.claude/commands/*.md`) | Thin, user-invoked entry point. (Commands are now a subset of skills; a skill of the same name wins.) |
| A **fragile / deterministic / consistency-critical** operation better done by exact code | **Script** (`scripts/` or a skill's `scripts/`) | Its code never enters context — only output does; reliable + token-cheap. |
| Copying data from a **system Claude can't see** | **MCP server** | External connection (out of scope for local scaffolding; note it and stop). |

## The decisive tie-breakers

- **Steer vs enforce.** Memory and skills are *requests Claude may follow*; hooks are
  *enforcement*. `"never edit .env"` in CLAUDE.md is a request — a `PreToolUse` hook that
  blocks the edit is a guarantee. If the requirement is a guarantee, it is a hook, full stop.
- **Fact vs procedure.** A *fact/convention* → CLAUDE.md/rule. A *procedure* → skill.
- **Content vs worker.** A **skill** adds reusable *content* to the current window; a
  **subagent** is an isolated *worker* in a separate window. Choose subagent when isolation,
  parallelism, or a restricted tool set is the point — not merely reuse.
- **Skill vs command.** Same trigger surface; use a **command** (or `disable-model-invocation`)
  when the action has side effects and only the human should fire it; use a **skill** when you
  also want auto-invocation and supporting files.

## Don't over-build

Per `sdlc-asset-authoring.md` and `code-quality.md`: check it doesn't already exist (extend
first), pick the **smallest** asset that works, and don't add a subagent/hook where a CLAUDE.md
line or a plain function would do.
