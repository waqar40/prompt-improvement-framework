# Instructional Semantics & Composition Consistency — Section G

The gate sections A–F (frontmatter, anatomy, the 7 NFR rubrics, permissions, model tier,
verification) judge whether an artifact is **built like good software**. This section judges a
different axis: whether the artifact's **prose is a good set of instructions to an LLM** — the
same axis `prompt-critic` applies to a one-shot prompt, applied here to an authored skill/agent/
command/rule's own body. An artifact can pass A–F (right shape, right tools, ships a test) and
still fail here (internally contradicts itself, or reads three ways at once).

Six checks. Each finding gets a `severity` (blocking/major/minor, same meaning as `quality-gate.md`)
and must cite the exact `file:line` — never a vibe.

## G1 — Contradiction

Two instructions in the same artifact (or an artifact and a file it composes with, see G6) that
cannot both be followed. Look for: a Constraints block that forbids what a numbered Step requires;
two Steps that prescribe opposite orders for the same action; a tool listed in frontmatter that a
Constraint then says never to use (or vice versa); a stated boundary ("read-only") contradicted by
a granted tool (`Edit`/`Write`). *Severity: blocking* — an LLM given contradictory instructions
picks one arbitrarily, which is a correctness failure, not a style nit.

## G2 — Semantic ambiguity

An instruction whose meaning a competent reader could resolve two different ways, where the
difference changes behavior. Look for: an unqualified pronoun standing in for more than one
plausible referent ("fix it" inside a multi-target step); a vague success word with no test
attached (`"appropriate"`, `"as needed"`, `"reasonable"` with no definition nearby — this is the
same D-series smell `prompt-critic`'s rubric flags in a sent prompt); a step whose trigger
condition is unstated ("if needed, …" with no criterion for *needed*). *Severity: major*, unless
the ambiguity sits on a blocking action (destructive op, write gate) — then *blocking*.

## G3 — Persona consistency (agents primarily; skills where they role-play)

Applies mainly to subagents, whose body opens with a role line. Check that the stated role/tone
holds for the whole body: a "senior security reviewer, terse and skeptical" role that later
instructs "be encouraging and add lots of caveats" is a persona contradiction, not a nuance. Also
flag a role claim the tool grant contradicts (an agent claiming authority to "decide and act" but
holding only `Read`/`Grep`/`Glob`). *Severity: major*.

## G4 — Cognitive load

Structural complexity that will cause the model to drop or misapply a rule, independent of length
limits (which section A already gates). Look for: more than ~3 levels of nested conditionals in
prose ("if X, unless Y, except when Z, but only if…"); a nu­mbered procedure whose steps are not
actually sequential (branches disguised as steps); a Constraints block mixing NEVER/ALWAYS with no
visual separation so the reader can't scan it. The fix is almost always restructuring (a table, a
decision tree, splitting into a sub-skill/reference), never just shortening prose.
*Severity: major*, or *minor* if the artifact is already within size limits and the nesting is
shallow (2 levels).

## G5 — Semantic coverage

A gap in what the artifact's Steps handle relative to what its description promises. Look for: a
description that promises handling an input type/edge case (e.g. "or a whole `.claude/` tree")
that no Step actually branches on; an error/failure path implied by the domain (empty input,
missing upstream artifact, tool call failure) with no instruction for what to do; a workflow that
ends with "write the file" but never says what happens if the write target already has unrelated
content. *Severity: major* if the gap is reachable in normal use, *minor* if it's a genuine edge case.

## G6 — Composition conflict

Checked whenever the artifact **references another file** — a skill's `references/` table, an
agent's "follow `~/.claude/skills/...`" line, a command's "read `<skill>.md` and follow it
exactly". Two failure modes:
1. **Dangling reference** — the referenced path does not exist, or the referencing table/line was
   never updated after the target moved/renamed. *Severity: blocking* (the artifact cannot do what
   it says).
2. **Instructional drift** — the referenced file exists but says something the referencing
   artifact's own body contradicts (e.g. the orchestrator's Step says "gate = FAIL on any blocking
   item", the reference file's roll-up allows a `PASS` with one blocking item outstanding). Read
   both files; diff the specific claim. *Severity: major*, *blocking* if the drift changes a
   pass/fail or destructive-action gate.

## Extension point — repo-local custom checks

A target repo may define extra checks (its own vocabulary, banned phrases, house style) without
touching this file: drop them at `<repo>/.claude/diagnostics.md` (or `.claude/rules/diagnostics.md`
if the repo already uses a `rules/` convention) as a plain list of `NEVER <pattern>` / `ALWAYS
<pattern>` lines, one per line, each with a one-line why. `artifact-reviewer` reads this file if
present (Step 3) and folds each hit in as a `G7` finding with the severity the repo file states
(default `minor` if unstated). This is the same extension point Microsoft's Chat Customizations
Evaluations extension exposes as `customDiagnostics` — kept here as a plain markdown file instead
of a settings key so it stays diffable and requires no editor/schema.

## Applying G to each type

| Type | G1 contra­diction | G2 ambiguity | G3 persona | G4 cog-load | G5 coverage | G6 composition |
|---|---|---|---|---|---|---|
| Skill | yes | yes | rarely (only if it role-plays) | yes | yes | yes (its `references/` table) |
| Subagent | yes | yes | **yes — primary** | yes | yes | yes (skills it's told to follow) |
| Command | yes (frontmatter vs body) | yes | n/a | rarely (thin by construction) | yes (does it forward everything the skill needs?) | **yes — primary** (the skill it wraps) |
| Rule | yes | yes | n/a | yes | n/a | yes (rules that reference other rules/tiers) |
| Script | n/a (code, not prose) | in `--help`/comments only | n/a | n/a | n/a | yes (callers that assume a since-changed CLI) |
