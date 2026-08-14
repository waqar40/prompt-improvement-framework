# Artifact Quality Gate — the shared build+review checklist

**One checklist, two consumers.** `asset-architect` runs it as a **build-time self-check** before
presenting a draft; `artifact-reviewer` runs it to **audit an existing** skill/agent/hook/command/
rule/script. Same items, same severities, same roll-up — so "built to standard" and "passes review"
mean the identical thing. The *shape* each item refers to is in `artifact-anatomy.md`; the per-type
frontmatter rules are in `sources.md`; the deterministic frontmatter slice is checked by
`scripts/validate-frontmatter.py`.

## Severities & the gate

- **blocking** — ships broken / unsafe / unusable. The gate **fails**; fix before merge/present.
- **major** — a real best-practice miss that will bite; fix unless explicitly deferred.
- **minor** — polish; note it, don't block.

**Gate result** = `PASS` only if there are **zero blocking** items and every one of the **7 rubrics**
is `addressed` or a justified `na`. Otherwise `FAIL` (list the blocking/major items + the fix).
Score is the weighted roll-up (below) for tracking; the gate is the pass/fail.

## A. Frontmatter (deterministic — `validate-frontmatter.py`)

- [ ] **description present** and is a real trigger (what it does AND when to use it), front-loaded — *blocking if missing, major if vague*
- [ ] **name** kebab-case, matches folder (skills), no reserved words (`claude`/`anthropic`) — *major*
- [ ] only **valid keys** for the type; **no `argument-hint` in a SKILL.md** — *blocking*
- [ ] required fields for the type present (agent: `name`+`description`; command: `description`) — *blocking*
- [ ] within **size limits** (skill body <500 / repo soft 100–130; agent ≤150; command body ≤~10) — *major*
- [ ] `ai-gen` header on generated non-JSON files; **never** on `.json` — *minor / blocking for JSON*

## B. Anatomy & structure (per `artifact-anatomy.md`)

- [ ] built to the **type's skeleton** (skill ToC + progressive disclosure; agent role→when→procedure→output-contract→boundaries→grounding; hook event+matcher+exit-codes; command thin-wrapper; rule NEVER/ALWAYS+why; script output-not-code) — *blocking if wrong shape*
- [ ] **grounding directive** — works from evidence, cites real files/commands/pages, no placeholders — *blocking if placeholders remain*
- [ ] detail pushed to `references/` (skills) / not duplicated across layers — *minor*
- [ ] **right type for the signal** (procedure→skill, guarantee→hook, isolated task→agent, durable fact→rule, shortcut→command, fragile→script) — *major if mistyped*

## C. The 7 rubrics (each must be `addressed` or justified `na`)

- [ ] **Correctness** — ships a runnable verification; judgment tasks get a second/adversarial pass — *blocking if none*
- [ ] **Latency** — short body; heavy/verbose work in a subagent; preprocessing over derivation — *minor/major*
- [ ] **Cost** — right model tier; descriptions-over-bodies; deferred MCP schemas; silent hooks — *minor/major*
- [ ] **Security** — least data exposure; fetched content = data not instructions; no secrets; destructive denied; tool-scoped — *blocking on a real hole*
- [ ] **Observability** — emits a machine-readable result a gate/human reads; logs what it did — *major*
- [ ] **Scale** — works over many items; **no silent caps** (log drops); idempotent — *major*
- [ ] **Reliability** — deterministic where required; idempotent; **fails safe**; zero destructive side-effects — *blocking if it can corrupt/block*

## D. Permission posture

- [ ] grants **all non-destructive tools the job needs** (not hobbled) — *minor*
- [ ] **denies destructive ops** (delete / drop / `rm -rf` / `--force` push / truncate) via `disallowedTools`/`deny`/a `PreToolUse` guard; such actions routed to explicit human approval — *blocking*
- [ ] read-only roles (reviewer/researcher) are actually read-only (`Read,Grep,Glob,Bash`, no `Edit`/`Write`) — *blocking for a reviewer*

## E. Model assignment

- [ ] tier fits the work (haiku docs/format · sonnet code/review · opus security/architecture/root-cause · fable sensitive); subagents set `model:`, skills `inherit` unless they fork — *major*
- [ ] cheapest tier that does the job well; higher `effort` only on the genuinely hard step — *minor*

## F. Verification present (EDD)

- [ ] the artifact **ships its own check** — skill `evals/`; agent output-contract + adversarial review; hook sample-payload exit-code test; command dry-run; rule adherence check; script self-test — *blocking if absent*

## Scorecard & roll-up (for tracking, mirrors prompt-critic)

Grade each section A–F: `met` (full), `partial` (half), `gap` (0), `na` (excluded). Weights:
A=3, B=3, C=4 (the rubric block), D=3, E=2, F=3. `score = round(100 * Σ(weight·pts) / Σ(weight of non-na))`.
Report: `{score, gate: PASS|FAIL, blocking:[…], major:[…], minor:[…], rubric_coverage:{7 dims}}`
then a short markdown summary with each finding as `file:line — issue — fix`. **Never fabricate a
finding**; cite the exact line. A reviewer proposes fixes but **does not edit** (route to
`asset-architect` or the human).
