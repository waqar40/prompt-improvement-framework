# Prompt Critic — Output Contract

Respond with **EXACTLY ONE JSON object first**, valid and parseable, with **no prose
before it**, matching this schema. After the closing brace, render a concise Markdown
summary for humans.

```json
{
  "task_inference": "string — the task as you understand it",
  "prompt_kind": "one_shot | system_prompt | chain_step | other",
  "assumptions": ["string — anything you had to assume"],
  "layer1_design": [
    {
      "id": "D1",
      "dimension": "string",
      "applicable": true,
      "verdict": "met | partial | gap | na",
      "severity": "blocking | major | minor | none",
      "evidence": "string — quote or paraphrase from the prompt justifying the verdict",
      "fix": "string — concrete change to make, or empty if met/na"
    }
  ],
  "layer2_evaluability": [
    {
      "id": "E1",
      "dimension": "string",
      "applicable": true,
      "verdict": "met | partial | gap | na",
      "severity": "blocking | major | minor | none",
      "evidence": "string",
      "fix": "string"
    }
  ],
  "overall": {
    "score": 0,
    "weight_total": 0,
    "verdict": "STRONG | ADEQUATE | WEAK | POOR | BLOCKED",
    "blocking_gaps": ["string — ids + one-line reason"],
    "top_fixes": ["string — the 1–3 highest-leverage changes, in priority order"]
  },
  "refined_prompt": "string — the rewritten prompt, ready to use",
  "chain": [
    { "step": 1, "prompt": "string", "why": "string" }
  ],
  "changelog": ["string — what changed and which gap id it closes"],
  "suggested_eval_criteria": [
    {
      "criterion": "string — a single MECE check for grading OUTPUTS of the refined prompt",
      "type": "deterministic | property | judge",
      "check": "binary | scale",
      "scale": "string — anchors if scale, e.g. 0=missing, 1=partial, 2=complete; empty if binary"
    }
  ],
  "guidance": ["string — durable advice for the author to internalize, not just this prompt's fixes"],
  "asset_hint": {
    "smells_reusable": false,
    "candidate_type": "skill | agent | command | hook | rule | script | none",
    "what": "string — the reusable capability this prompt hints at, or empty",
    "why": "string — the signal (repeated procedure, guaranteed action, isolated task, durable fact...), or empty"
  },
  "execution_context": {
    "assets_used": ["string — verbatim lines from the journal's assets-used block, or [] if not supplied"],
    "consistency_note": "string — one line: did what ran match what the prompt asked for? empty if assets_used was not supplied"
  }
}
```

## Rules for the contract

- `chain` is an empty array unless you are recommending decomposition.
- `suggested_eval_criteria` must be checkable against OUTPUTS of the refined prompt, be
  MECE, favor binary yes/no criteria, and tag each as `deterministic` (mechanical),
  `property` (structural/invariant), or `judge` (needs an LLM/human rating). Put
  deterministic checks first.
- Every `blocking_gap` id must have a corresponding `changelog` entry showing it is closed
  by the refined prompt.
- Never fabricate evidence. If the prompt is empty or unintelligible, return a single
  `blocking` E1 gap and ask for the task intent in `top_fixes`.
- `asset_hint` is OPTIONAL and never affects the score. Emit it only when the prompt
  smells like a *reusable* need (a procedure you'd repeat → `skill`; a "whenever X do Y"
  guarantee → `hook`; an isolated multi-step delegated task → `agent`; a durable
  fact/convention → `rule`; a typed-to-start shortcut → `command`; fragile deterministic
  work → `script`). Set `smells_reusable: false` and `candidate_type: "none"` otherwise.
  A single prompt cannot know it recurs — that is the aggregator's job (`asset-suggester`);
  here just flag the *shape*. Cross-reference `~/.claude/rules/` conventions where relevant.
- `execution_context` is OPTIONAL and never affects the score — it is transparency, not a
  rubric dimension. Populate it only when `assets_used` was supplied as an input; otherwise
  leave `assets_used: []` and `consistency_note: ""`. See `references/rubric.md`'s "Using
  `assets_used` context" note for how (not whether) it may sharpen an existing gap's evidence.

## Markdown summary (after the JSON)

Keep it short: verdict, score, blocking gaps, top fixes, and the refined prompt. No
flattery, no restating the rubric.
