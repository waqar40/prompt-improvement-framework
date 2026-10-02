# Per-User Guide Format — source JSON + rendered views

The guide lives under the **outcomes dir** `<outcomes>` (`PROMPT_OUTCOMES_DIR`, default
`~/.claude/prompt-journal/prompts-review-outcomes`), never inside the plugin. The **source of truth is
`<outcomes>/guides/<user>.json`**; the `.md`, `.pdf`, and `.docx` beside it are **rendered views**
produced by `python scripts/render-guide.py <outcomes>/guides/<user>.json`. Never hand-edit the
views — edit the JSON and re-render. Update the JSON in place (merge, never clobber).

**The guide is the compiled, overall view.** It is grounded in the **whole score store**
(`scores/<user>.jsonl`, every file/project), not a single run — so its snapshot, strengths,
and weaknesses reflect the user's real overall state. Per-file, per-session outcomes live
separately in `<outcomes>/reviews/<user>/<branch-slug>.md` (written by the pipeline).

## JSON schema

```json
{
  "user": "<user>",
  "updated": "<YYYY-MM-DD>",
  "source": "whole journal (all logs) | <path, if the run was narrowed>",
  "snapshot": {
    "reviewed": 42, "excellent": 8, "good": 20, "bad": 14,
    "trend": "<improving / flat / regressing on which dimensions>",
    "common_gap": "<dimension + one line — the overall recurring weakness>",
    "strongest_habit": "<dimension + one line — the overall recurring strength>",
    "coverage": {
      "files": 7,
      "projects": ["<project name>", "..."],
      "from": "<YYYY-MM-DD earliest>", "to": "<YYYY-MM-DD latest>"
    }
  },
  "focus_plan": {
    "dimension": "<D1-D10|E1-E4, or null if no progress data yet>",
    "label": "<dimension label>",
    "one_line": "<progress-coach's teaser — one clause of its rationale>",
    "pace": "improving_fast | improving_slow | flat | regressing | insufficient_data",
    "regression_count": 0,
    "provisional": false
  },
  "sections": [
    {
      "band": "excellent | good | bad",
      "title": "What excellent looks like | Good, one fix away | Anti-patterns to kill",
      "examples": [ <example> ]
    }
  ],
  "habits_build": ["<durable guideline applied before sending>"],
  "habits_have":  ["<recurring strength worth keeping>"]
}
```

`focus_plan` is written verbatim from `progress-coach`'s teaser (Step 5 of `prompt-journal`) —
the curator never derives it itself. Omit the whole key (not just null fields) if `progress-coach`
returned nothing (e.g. this repo predates the adaptive-coaching upgrade and has no
`progress/<user>.json` yet) — the renderer skips the section entirely rather than printing an
empty one. Full detail (per-dimension levels, concrete steps, regression alerts) lives in
`<outcomes>/progress/<user>.md`, linked from the rendered teaser, not duplicated here.

### Example object — the important part

Every example carries a **full 14-row rubric** and a **transformation table**:

```json
{
  "label": "<short label of the lesson>",
  "score": 72,
  "verdict": "STRONG | ADEQUATE | WEAK | POOR | BLOCKED",
  "kind": "one_shot | chain_step | system_prompt",
  "date": "<YYYY-MM-DD>",
  "prompt": "<the prompt, exactly as sent — verbatim, never paraphrased>",
  "why": "<one paragraph: the driving dimensions>",
  "chain": "<optional: how session context resolved the reference>",
  "rubric": [
    {"id": "D1", "verdict": "met | partial | gap | na", "sev": "blocking | major | minor | none",
     "evidence": "<quote/paraphrase justifying the verdict>"}
    // ... one row for EACH of D1-D10, E1-E4 (14 rows total, in that order)
  ],
  "transformation": [
    {"id": "<rubric id the gap maps to>", "before": "<what the user wrote>",
     "after": "<the best-practice rewrite of that fragment>",
     "principle": "<the durable prompt-engineering rule it teaches>"}
    // one row per partial/gap worth teaching; [] for a clean excellent prompt
  ],
  "fix": "<the full rewritten prompt, ready to use — omit for excellent>"
}
```

### Rules that keep the tables trustworthy

- **All 14 rubric rows, every example** (D1–D10 then E1–E4). Mark dimensions the task does
  not need as `verdict: "na"` — do not drop them; the point is to show *on what grounds*
  the prompt was reviewed, including what was out of scope.
- **The rubric must reproduce the score.** The renderer recomputes the weighted roll-up
  (`met` = full weight, `partial` = half, `gap` = 0, `na` = excluded) and prints a WARNING
  if it disagrees with the stored `score`. Weights are the prompt-critic rubric
  (D1/D2/E1/E2 = 3, D3/D4/D5/D6/D9/D10/E3/E4 = 2, D7/D8 = 1). Tune verdicts until it
  matches; never invent a score the rubric can't justify.
- **Transformation rows are `before → after`** for the fragment, plus the principle — this
  is the teaching payload. Excellent prompts have `transformation: []` and render as
  "No changes needed — imitate this one."
- Verdict/score come from prompt-critic; the curator maps them into rows, it does not
  re-score.

## Rendered layout (all three views)

- **Snapshot** chips (excellent/good/bad/reviewed) + most-common-gap / strongest-habit +
  a "how to read" legend.
- **Your Focus Right Now** (only if `focus_plan` is present) — one short paragraph: dimension,
  the one-line rationale, pace, a regression-alert count if non-zero, and a pointer to the full
  `progress/<user>.md` plan. Omitted entirely, not printed empty, when `focus_plan` is absent.
- Three banded sections. Each example renders: header (band · score · verdict · label),
  the verbatim prompt, "Why it lands here", optional "Chain step", the **rubric scorecard
  table** (Rubric dimension | Status | Why), the **transformation table** (Rubric | You
  wrote | Best-practice rewrite | Principle), and the **full rewritten prompt**.
- **Habits to build** and **Habits you already have**.

## Merge discipline

- Keep examples that still teach; replace an example only with a sharper one for the same
  lesson; update the Snapshot every pass.
- Deduplicate — do not accumulate near-identical examples of the same failure mode.
- Never edit the raw journal logs or the rendered views from here; the JSON is the only
  thing you edit, then re-render.
