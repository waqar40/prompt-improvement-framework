# The Written Plan — prepare it, then follow it

Two things this file defines:
1. **The architect's own plan** — what `asset-architect` must write and present, after research
   and before drafting any artifact content, every single time it scaffolds something.
2. **The plan-first requirement every scaffolded skill/agent must itself carry** — the fourth
   universal law in `artifact-anatomy.md`, applied proportionally to the artifact's stakes.

## 1. The architect's own plan

After Steps 1–4 (grounding brief, research brief, type, placement), write the **approach**, not
the artifact's content yet:

```
PLAN
- Need (one line): <what's being solved, in the user's own words>
- Chosen type + why: <type, the one-line signal that drove it>
- Placement: <exact destination path + why>
- Grounded on: <the grounding brief's anchors, condensed>
- Research findings: <research brief's key points — sources, edge cases flagged, Responsible AI notes>
- Verification approach: <which Section F check this artifact ships, and confirmation it will be a
  real file written to disk, not a description>
- Open questions: <anything still needing the user's answer before drafting>
```

**Present this plan before drafting.** If it carries open questions, stop and ask them — do not
fill a gap with an assumption. Once the plan is confirmed (explicitly, or without objection when
shown alongside the draft at the approval gate), the draft must **trace back to it line for
line** — every section of the drafted artifact corresponds to something the plan said. If drafting
reveals the plan was wrong (a grounded fact turns out to be stale, a placement doesn't fit), say so
and restate the plan — never silently diverge from a plan the user already saw.

## 2. The rule every scaffolded skill/agent must also carry

Every skill/subagent this tool emits must itself instruct its own executor to **plan before
acting**, scaled to the artifact's stakes — this is not optional polish, it is gate check H1:

| Artifact's stakes | What its own body must instruct |
|---|---|
| Simple, read-only, single-step (a lookup, a formatter) | One line is enough — e.g. "state what you're about to check before running it." |
| Multi-step or write-capable | An explicit early step: "Before making any change, state the plan — the steps you'll take and why — then follow it; if a step reveals the plan was wrong, say so and restate it before continuing." |
| Destructive-adjacent (can delete/overwrite/force-push/approve a high-stakes action) | The plan step is **mandatory and blocking**: no destructive action without both a stated plan AND an explicit human-approval gate — ties directly to the permission posture in `artifact-anatomy.md`. |

An artifact whose stakes call for a plan step and doesn't have one fails gate Section H1
(`quality-gate.md`) — this is checked the same way for every type, by both `asset-architect`
(build-time) and `artifact-reviewer` (audit-time).
