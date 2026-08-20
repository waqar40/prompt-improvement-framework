We spend hours a day writing prompts for AI coding assistants — and almost none of us ever go back and check whether we're any good at it.

So I built a system that does that for me: **Prompt Journal**.

It's a lightweight, open-source framework that turns "I hope my prompts are decent" into an actual feedback loop:

→ **Records every prompt automatically.** A single Claude Code hook captures what you actually type, verbatim, per project and branch — no copy-pasting into a spreadsheet.

→ **Scores each one against a real rubric**, not vibes — 14 dimensions covering design (clarity, specificity, grounding, examples, framing...) and evaluability (is success even defined? measurable? are failure modes anticipated?). Short follow-up turns like "push it" or "merge the PR" are judged fairly as chain steps, not penalized for brevity.

→ **Builds you a personal guide** — your actual excellent, good, and weak prompts, each with a rubric scorecard, a before → after rewrite, and the durable habit it teaches. Rendered as Markdown, PDF, and Word.

→ **Spots recurring work and proposes reusable assets** — when you keep doing the same multi-step thing, it flags it as a candidate skill, subagent, hook, or command, grounded in your real repo, and scaffolds it only after you approve.

→ **Ships its own quality gate and test harness**, so the tooling reviewing your prompts is held to the same bar it holds you to.

The part I actually care about: it's a real Claude Code plugin. `/plugin marketplace add` + `/plugin install`, and you're done — recorder hook wired automatically, directories created, even the Python dependencies for PDF/Word rendering are pinned and auto-installed. No manual `pip install`, no dependency hunting, nothing to configure by hand. Everyone on a team runs the same two commands and gets their own private journal.

Your raw prompts and scores never touch the shared repo — they live under your own `~/.claude/prompt-journal/` on your machine. The plugin itself is machinery only.

If you're trying to get better at working with AI coding tools — or want your team to — the code's here:
https://github.com/waqar40/prompt-improvement-framework

#PromptEngineering #ClaudeCode #DeveloperTools #AI #OpenSource
