# ai-gen — deterministic engine behind the progress-coach skill.
"""Usage: python3 scripts/compute-progress.py SCORES_JSONL --user NAME [--prev PROGRESS_JSON] [--out PROGRESS_JSON]

Reads the append-only score store (<outcomes>/scores/<user>.jsonl), computes a per-dimension
EWMA level + confidence (Glicko-style deviation), classifies pace between the last two /analyse
"checkpoints" (grouped by each row's run_id, falling back to date for legacy rows with no
run_id), applies Bloom-floor + hysteresis mastery gating, and picks the single next focus
dimension via a Theory-of-Constraints bottleneck rule with deterministic tie-breaks.

Pure stdlib, deterministic, no LLM call — see docs/adr/0001-adaptive-personalized-progress-coaching.md
for the algorithm and its justification, and skills/progress-coach/references/algorithm.md for the
skill-facing mirror of this same spec. This script computes the NUMBERS; the progress-coach skill
turns them into human-readable rationale + concrete improvement steps.

Never edits the score store (read-only). Writes the new progress.json atomically (temp file +
rename) so a crash mid-write can never corrupt the previous, valid state.

Exit code: 0 on success, 1 on a fatal input error (missing/unreadable score store).
"""
import json
import math
import os
import sys
import tempfile
from datetime import datetime, timezone

# --- Constants (see ADR 0001 for the justification behind each) --------------------------------
LAMBDA = 0.25          # EWMA weight
K0 = 2.0               # Bayesian shrinkage pseudo-count toward PRIOR_MU
PRIOR_MU = 0.5         # neutral prior level
N_MIN = 6              # minimum real observations before a dimension is "trustable"
MASTER_FLOOR = 0.85    # Bloom-style mastery criterion
MASTER_CIGATE = 0.80   # confidence lower-bound must also clear this to graduate
DEMOTE_FLOOR = 0.70    # hysteresis: once mastered, only demoted below this
STALL_RUNS = 3         # consecutive flat runs on the same focus before escalating tactic
Z = 1.0                # dead-band width, in standard errors
PACE_FAST = 0.12       # asymmetric thresholds: improving must clear this to be "fast"
PACE_REGRESS = 0.06    # regressing needs only this much of a drop (flag earlier than we celebrate)

VERDICT_VALUE = {"met": 1.0, "partial": 0.5, "gap": 0.0}  # "na" is dropped, not zero

DIMENSIONS = {
    "D1": "Clarity & explicitness", "D2": "Specificity & constraints",
    "D3": "Output format & length", "D4": "Context & motivation",
    "D5": "Grounding / reference", "D6": "Examples (show-not-tell)",
    "D7": "Positive framing", "D8": "Uncertainty handling",
    "D9": "Decomposition fit", "D10": "Structural economy",
    "E1": "Success is defined", "E2": "Criteria are measurable",
    "E3": "Multidimensional coverage", "E4": "Failure modes anticipated",
}
# Foundational-first tie-break order (lower index = coached first on a tie). See ADR 0001.
PRIORITY = ["D1", "D2", "E1", "E2", "D4", "D5", "D9", "D3", "E4", "E3", "D10", "D7", "D6", "D8"]


def load_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue  # skip a corrupt line rather than abort the whole run
    return rows


def group_checkpoints(rows):
    """Group rows into ordered (checkpoint_id, [rows]) by run_id, falling back to date for
    legacy rows that predate the run_id field. Returns checkpoints in chronological order."""
    buckets = {}
    order = []
    for r in rows:
        cp = r.get("run_id") or r.get("date") or "unknown"
        if cp not in buckets:
            buckets[cp] = []
            order.append(cp)
        buckets[cp].append(r)
    order.sort()  # ISO run_id and YYYY-MM-DD date both sort chronologically as strings
    return [(cp, buckets[cp]) for cp in order]


def dim_observations_by_checkpoint(checkpoints, dim):
    """For one dimension, return [(checkpoint_id, [numeric obs from that checkpoint's rows])]."""
    out = []
    for cp_id, rows in checkpoints:
        obs = []
        for r in rows:
            dims = r.get("dims") or {}
            v = dims.get(dim)
            if v in VERDICT_VALUE:
                obs.append(VERDICT_VALUE[v])
        out.append((cp_id, obs))
    return out


def snapshot_level(ewma, n_total):
    """Bayesian-shrunk level + Glicko-style deviation at a given (ewma, n_total) point."""
    if n_total <= 0:
        L = PRIOR_MU
        RD = math.sqrt(PRIOR_MU * (1 - PRIOR_MU) / K0)
        return L, RD
    L = (n_total * ewma + K0 * PRIOR_MU) / (n_total + K0)
    n_eff = min(n_total, (2 - LAMBDA) / LAMBDA)
    RD = math.sqrt(max(L * (1 - L), 1e-9) / (n_eff + K0))
    return L, RD


def compute_dimension_trajectory(checkpoints, dim):
    """Walk every checkpoint in order, updating one running EWMA, and snapshot (checkpoint_id,
    L, RD, n_total) at each checkpoint boundary — this is what lets us diff level between the
    last two checkpoints for pace, using only observations available up to each point."""
    ewma = PRIOR_MU
    n_total = 0
    traj = []
    for cp_id, obs in dim_observations_by_checkpoint(checkpoints, dim):
        for o in obs:
            ewma = LAMBDA * o + (1 - LAMBDA) * ewma
            n_total += 1
        L, RD = snapshot_level(ewma, n_total)
        traj.append({"checkpoint": cp_id, "level": L, "deviation": RD, "n_total": n_total})
    return traj


def ols_slope(points):
    """Simple least-squares slope of level vs. checkpoint index (0,1,2,...). points: list of
    (x, y). Returns slope, or None if fewer than 2 distinct x values."""
    n = len(points)
    if n < 2:
        return None
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    mx = sum(xs) / n
    my = sum(ys) / n
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den = sum((x - mx) ** 2 for x in xs)
    if den == 0:
        return None
    return num / den


def classify_pace(delta, se):
    band = max(Z * se, 0)
    if delta > max(band, PACE_FAST):
        return "improving_fast"
    if delta > band:
        return "improving_slow"
    if delta < -max(band, PACE_REGRESS):
        return "regressing"
    return "flat"


def is_mastered(level, ci_low, pace, n_total, prev_mastered):
    if n_total < N_MIN:
        return False
    if prev_mastered:
        return level >= DEMOTE_FLOOR  # hysteresis: only lose mastery below the lower floor
    return level >= MASTER_FLOOR and ci_low >= MASTER_CIGATE and pace != "regressing"


def compute(score_rows, prev_state, run_id_hint=None):
    checkpoints = group_checkpoints(score_rows)
    n_checkpoints = len(checkpoints)
    cold_start = n_checkpoints <= 1

    prev_mastered_map = (prev_state or {}).get("state", {}).get("prev_mastered", {})
    prev_focus = (prev_state or {}).get("state", {}).get("prev_focus")
    prev_stall = (prev_state or {}).get("state", {}).get("stall_runs", {})

    dims_out = {}
    any_trustable = False
    for d, label in DIMENSIONS.items():
        traj = compute_dimension_trajectory(checkpoints, d)
        if not traj:
            dims_out[d] = {
                "label": label, "n_obs": 0, "level": PRIOR_MU, "deviation": None,
                "ci_low": None, "ci_high": None, "pace": "insufficient_data", "delta": None,
                "mastered": False, "trustable": False,
            }
            continue
        cur = traj[-1]
        n_total = cur["n_total"]
        trustable = n_total >= N_MIN
        any_trustable = any_trustable or trustable

        pace = "insufficient_data"
        delta = None
        if len(traj) >= 2 and not cold_start:
            prev = traj[-2]
            se = math.sqrt(cur["deviation"] ** 2 + prev["deviation"] ** 2)
            if len(traj) >= 4:  # >=3 checkpoint LEVELS (traj includes a 0th cold entry too)
                recent = [(i, t["level"]) for i, t in enumerate(traj[-3:])]
                slope = ols_slope(recent)
                if slope is not None:
                    delta = slope
                    pace = classify_pace(delta, se)
                else:
                    delta = cur["level"] - prev["level"]
                    pace = classify_pace(delta, se)
            else:
                delta = cur["level"] - prev["level"]
                pace = classify_pace(delta, se)

        prev_mastered = bool(prev_mastered_map.get(d, False))
        mastered = False if cold_start else is_mastered(
            cur["level"], cur["level"] - Z * cur["deviation"], pace, n_total, prev_mastered)

        dims_out[d] = {
            "label": label,
            "n_obs": n_total,
            "level": round(cur["level"], 4),
            "deviation": round(cur["deviation"], 4),
            "ci_low": round(max(0.0, cur["level"] - Z * cur["deviation"]), 4),
            "ci_high": round(min(1.0, cur["level"] + Z * cur["deviation"]), 4),
            "pace": pace,
            "delta": round(delta, 4) if delta is not None else None,
            "mastered": mastered,
            "trustable": trustable,
        }

    # --- regression alerts: was mastered before, now regressing (independent of focus) --------
    regression_alerts = []
    for d, info in dims_out.items():
        if prev_mastered_map.get(d) and info["pace"] == "regressing":
            regression_alerts.append({
                "dimension": d, "label": info["label"],
                "level": info["level"], "delta": info["delta"],
            })

    # --- next focus: momentum first (stick with prior focus until it graduates), else bottleneck
    stall_runs_out = {}
    if cold_start or not any_trustable:
        candidates = [d for d, i in dims_out.items() if i["n_obs"] > 0] or list(DIMENSIONS)
        candidates.sort(key=lambda d: (dims_out[d]["level"], PRIORITY.index(d)))
        focus_dim = candidates[0] if candidates else None
        focus = {
            "dimension": focus_dim, "label": DIMENSIONS.get(focus_dim, ""),
            "reason": "provisional — not enough history yet to trust a real ranking",
            "level": dims_out[focus_dim]["level"] if focus_dim else None,
            "pace": "insufficient_data", "stall_runs": 0, "provisional": True,
        } if focus_dim else None
    else:
        pace_rank = {"regressing": 0, "flat": 1, "improving_slow": 2, "improving_fast": 3, "insufficient_data": 1}
        if prev_focus and prev_focus in dims_out and not dims_out[prev_focus]["mastered"] \
                and dims_out[prev_focus]["trustable"]:
            focus_dim = prev_focus
            reason = "staying on your current focus — one habit at a time until it's mastered"
        else:
            candidates = [d for d, i in dims_out.items() if i["trustable"] and not i["mastered"]]
            if not candidates:
                mastered_dims = [d for d, i in dims_out.items() if i["mastered"]]
                focus_dim = min(mastered_dims, key=lambda d: dims_out[d]["level"]) if mastered_dims else None
                reason = "maintenance — every trustable dimension is currently mastered"
            else:
                candidates.sort(key=lambda d: (
                    dims_out[d]["level"], pace_rank.get(dims_out[d]["pace"], 1),
                    PRIORITY.index(d), dims_out[d]["n_obs"]))
                focus_dim = candidates[0]
                reason = "lowest trustable, not-yet-mastered dimension"

        stall = prev_stall.get(focus_dim, 0) if focus_dim else 0
        if focus_dim and dims_out[focus_dim]["pace"] == "flat" and focus_dim == prev_focus:
            stall += 1
        elif focus_dim != prev_focus:
            stall = 0
        elif dims_out.get(focus_dim, {}).get("pace") in ("improving_fast", "improving_slow"):
            stall = 0
        if focus_dim:
            stall_runs_out[focus_dim] = stall

        focus = {
            "dimension": focus_dim, "label": DIMENSIONS.get(focus_dim, "") if focus_dim else "",
            "reason": reason, "level": dims_out[focus_dim]["level"] if focus_dim else None,
            "pace": dims_out[focus_dim]["pace"] if focus_dim else None,
            "stall_runs": stall, "provisional": False,
            "escalate": stall >= STALL_RUNS,
        } if focus_dim else None

    mastered_dimensions = sorted([d for d, i in dims_out.items() if i["mastered"]])

    new_prev_mastered = {d: dims_out[d]["mastered"] for d in DIMENSIONS}
    state = {
        "prev_mastered": new_prev_mastered,
        "prev_focus": focus["dimension"] if focus else None,
        "stall_runs": stall_runs_out,
    }

    return {
        "cold_start": cold_start,
        "n_checkpoints": n_checkpoints,
        "dimensions": dims_out,
        "focus": focus,
        "regression_alerts": regression_alerts,
        "mastered_dimensions": mastered_dimensions,
        "checkpoints": [cp for cp, _ in checkpoints],
        "state": state,
    }


def main(argv):
    if len(argv) < 1:
        print("usage: compute-progress.py SCORES_JSONL --user NAME [--prev PROGRESS_JSON] [--out PROGRESS_JSON]", file=sys.stderr)
        return 1
    scores_path = argv[0]
    args = argv[1:]

    def flag(name, default=None):
        if name in args:
            i = args.index(name)
            return args[i + 1] if i + 1 < len(args) else default
        return default

    user = flag("--user", "unknown")
    prev_path = flag("--prev")
    out_path = flag("--out")

    if not os.path.isfile(scores_path):
        print(f"ERROR: score store not found: {scores_path}", file=sys.stderr)
        return 1

    rows = load_jsonl(scores_path)
    prev_state = None
    if prev_path and os.path.isfile(prev_path):
        try:
            with open(prev_path, encoding="utf-8") as f:
                prev_state = json.load(f)
        except json.JSONDecodeError:
            prev_state = None  # corrupt prior state -> treat as no history rather than crash

    result = compute(rows, prev_state)
    result["user"] = user
    result["updated"] = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    out = json.dumps(result, indent=2) + "\n"
    if out_path:
        d = os.path.dirname(os.path.abspath(out_path))
        os.makedirs(d, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".progress-", suffix=".json.tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(out)
            os.replace(tmp, out_path)  # atomic on POSIX and Windows
        except Exception:
            if os.path.exists(tmp):
                os.remove(tmp)
            raise
    else:
        print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
