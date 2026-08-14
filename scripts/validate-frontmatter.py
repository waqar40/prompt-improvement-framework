# ai-gen — deterministic front-matter validator for Claude Code assets (skills / commands / agents).
"""Usage: python scripts/validate-frontmatter.py [PATH ...]

Checks the frontmatter slice of the quality gate (references/quality-gate.md, section A) for
skills (SKILL.md), slash commands (.claude/commands/*.md), and subagents (.claude/agents/*.md).
Deterministic and cross-platform (pure stdlib). Default PATH = ./.claude . Exit non-zero if any
ERROR is found (WARN does not fail). Wireable as a PostToolUse hook or a CI gate.
"""
import re, sys, pathlib

ERRORS = 0; WARNS = 0
RESERVED = ("claude", "anthropic")

def parse_frontmatter(text):
    """Return (fm_dict, body_line_count). fm_dict maps top-level key -> raw value (first line)."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, len(lines)
    fm, i = {}, 1
    while i < len(lines) and lines[i].strip() != "---":
        m = re.match(r"^([A-Za-z0-9_-]+):\s?(.*)$", lines[i])
        if m:
            fm[m.group(1)] = m.group(2).strip()
        i += 1
    body = lines[i + 1:] if i < len(lines) else []
    body_nonempty = [l for l in body if l.strip()]
    return fm, len(body_nonempty)

def kind_of(path):
    p = path.as_posix()
    if path.name == "SKILL.md": return "skill"
    if "/commands/" in p and path.suffix == ".md": return "command"
    if "/agents/" in p and path.suffix == ".md": return "agent"
    return None

def report(path, level, msg):
    global ERRORS, WARNS
    if level == "ERROR": ERRORS += 1
    else: WARNS += 1
    print(f"  [{level}] {path}: {msg}")

def check(path):
    kind = kind_of(path)
    if not kind:
        return
    text = path.read_text(encoding="utf-8", errors="replace")
    fm, body_lines = parse_frontmatter(text)
    if fm is None:
        report(path, "ERROR", f"{kind}: no frontmatter block (must start with '---')")
        return
    desc = fm.get("description", "")
    # --- description (all types) ---
    if not desc:
        report(path, "ERROR", "description is missing (it is the trigger Claude matches)")
    elif len(desc) < 40:
        report(path, "WARN", "description is very short — state what it does AND when to use it")
    if kind == "skill" and len(desc) > 1024:
        report(path, "WARN", f"description is {len(desc)} chars (>1024 listing cap) — front-load it")
    # --- name (skill/agent) ---
    name = fm.get("name", "")
    if kind == "agent" and not name:
        report(path, "ERROR", "agent: 'name' is required")
    if name:
        if not re.match(r"^[a-z0-9]+(-[a-z0-9]+)*$", name):
            report(path, "WARN", f"name '{name}' is not lowercase-kebab-case")
        if any(r in name.lower() for r in RESERVED):
            report(path, "ERROR", f"name '{name}' uses a reserved word ({'/'.join(RESERVED)})")
        if kind == "skill" and name != path.parent.name:
            report(path, "WARN", f"name '{name}' != folder '{path.parent.name}' (should match)")
    # --- per-type ---
    if kind == "skill":
        if "argument-hint" in fm:
            report(path, "ERROR", "'argument-hint' is invalid in SKILL.md (belongs to slash commands)")
        if body_lines > 500:
            report(path, "ERROR", f"body is {body_lines} lines (>500) — push detail into references/")
        elif body_lines > 130:
            report(path, "WARN", f"body is {body_lines} lines (>130 orchestrator hard-limit) — trim or extract")
    elif kind == "command":
        if "argument-hint" not in fm:
            report(path, "WARN", "command: 'argument-hint' recommended for autocomplete")
        if "allowed-tools" not in fm:
            report(path, "WARN", "command: 'allowed-tools' recommended (scope narrowly)")
        if body_lines > 15:
            report(path, "WARN", f"command body is {body_lines} lines — keep it a thin wrapper (read a skill)")
    elif kind == "agent":
        if "tools" not in fm:
            report(path, "WARN", "agent: no 'tools' allowlist — inherits ALL tools (least-privilege preferred)")
        if "model" not in fm:
            report(path, "WARN", "agent: no 'model' — assign a tier (haiku/sonnet/opus/fable) or 'inherit'")
        if body_lines > 150:
            report(path, "WARN", f"agent body is {body_lines} lines (>150) — delegate detail to a skill")

def iter_targets(root):
    if root.is_file():
        yield root; return
    for pat in ("**/SKILL.md", "commands/**/*.md", "agents/**/*.md",
                "**/commands/**/*.md", "**/agents/**/*.md"):
        yield from root.glob(pat)

def main():
    args = sys.argv[1:] or [".claude"]
    seen = set()
    print("frontmatter validation:")
    n = 0
    for a in args:
        root = pathlib.Path(a)
        if not root.exists():
            report(root, "ERROR", "path does not exist"); continue
        for f in iter_targets(root):
            rp = f.resolve()
            if rp in seen: continue
            seen.add(rp); n += 1
            check(f)
    print(f"\nchecked {n} asset file(s): {ERRORS} error(s), {WARNS} warning(s)")
    return 1 if ERRORS else 0

if __name__ == "__main__":
    sys.exit(main())
