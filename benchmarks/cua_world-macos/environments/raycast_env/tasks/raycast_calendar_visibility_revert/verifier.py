"""Verifier for raycast_calendar_visibility_revert.

Tests whether the agent:
(a) modified the Mail draft (pasted something where the blank line was),
(b) included the distinctive free time blocks for Personal+Family only,
(c) excluded Work-calendar events (the trap — including Work would erase the
    13:00-14:00 free block via the seeded 'Team retro' event),
(d) touched Raycast's settings DB (best-effort signal that Raycast was used).

Scoring (100 pts, pass >= 70):
  C1 — Mail draft was modified (length > seeded baseline)              20 pts
  C2 — Mentions 1pm-2pm OR 13:00-14:00 free block                      30 pts
        (this block disappears if the agent wrongly includes Work)
  C3 — Mentions 4:30pm-5pm OR 16:30-17:00 free block                   25 pts
        (distinctive boundary; hard to fake)
  C4 — Does NOT mention any Work-calendar event (Team retro / standup) 15 pts
        AND does NOT mention 'yoga' (tentative event also excluded)
  C5 — Raycast WAL changed mtime (signal that Raycast was interacted   10 pts
        with — could not directly inspect calendar visibility setting)

Verification surface notes:
- Raycast Calendar visibility state lives in encrypted DB; we cannot
  directly verify the revert. We accept the WAL-mtime change as a weak
  proxy that the agent touched Raycast at all.
- Time-text matching is intentionally fuzzy across formats
  (1-2pm, 1:00 PM - 2:00 PM, 13:00-14:00, etc.).
"""

import json
import os
import re
import tempfile

PASS_THRESHOLD = 70

CRITERION_POINTS = {
    "C1_draft_modified":    20,
    "C2_first_block":       30,
    "C3_last_block":        25,
    "C4_excludes_traps":    15,
    "C5_raycast_touched":   10,
}

# Seeded baseline content length is ~140 chars; agent must add real content
# (~50+ chars for 3 availability blocks). 180 catches stubbed/empty fills
# without rejecting agents who add minimal but valid content.
DRAFT_BASELINE_MIN_LEN = 180

# Regex patterns
WORK_EVENT_TRAPS = [
    re.compile(r"\bteam\s*retro\b", re.IGNORECASE),
    re.compile(r"\bstandup\b",       re.IGNORECASE),
    re.compile(r"\bengineering\b",   re.IGNORECASE),
]
TENTATIVE_TRAP = re.compile(r"\byoga\b", re.IGNORECASE)


def _has_time_block(text, start_h, start_m, end_h, end_m):
    """Loose check that a time block from (start_h:start_m) to (end_h:end_m)
    is mentioned in `text` in any of several formats. Both endpoints must
    appear within ~40 chars of each other."""
    t = text.lower()

    def patterns_for(h, m):
        pats = []
        # 24-hour: 13:00 or 13:30
        pats.append(rf"\b{h:02d}:{m:02d}\b")
        # 12-hour: 1:00 pm / 1pm / 1:30 pm
        h12 = h % 12 or 12
        ampm = "pm" if h >= 12 else "am"
        if m == 0:
            pats.append(rf"\b{h12}\s*{ampm}\b")
            pats.append(rf"\b{h12}:00\s*{ampm}\b")
            pats.append(rf"\b{h12}:00\b")  # bare time, ambiguous
        else:
            pats.append(rf"\b{h12}:{m:02d}\s*{ampm}\b")
            pats.append(rf"\b{h12}:{m:02d}\b")
        return pats

    start_pats = patterns_for(start_h, start_m)
    end_pats   = patterns_for(end_h, end_m)

    for sp in start_pats:
        for sm_match in re.finditer(sp, t):
            sp_pos = sm_match.start()
            for ep in end_pats:
                for em_match in re.finditer(ep, t):
                    ep_pos = em_match.start()
                    delta = ep_pos - sp_pos
                    if 0 < delta < 40:
                        return True
    return False


def verify_calendar_visibility_revert(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/raycast_calendar_visibility_revert_result.json"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()

    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []
    subscores = {}

    draft_content = result.get("mail_draft_content", "") or ""
    draft_len     = result.get("mail_draft_length", 0)
    wal_changed   = result.get("raycast_wal_changed_after_setup", False)

    # C1 — Mail draft modified
    if draft_len >= DRAFT_BASELINE_MIN_LEN:
        score += CRITERION_POINTS["C1_draft_modified"]
        subscores["C1"] = CRITERION_POINTS["C1_draft_modified"]
        feedback.append(f"C1 PASS: mail draft length {draft_len} >= baseline {DRAFT_BASELINE_MIN_LEN}")
    else:
        subscores["C1"] = 0
        feedback.append(f"C1 FAIL: mail draft length {draft_len} <= baseline; agent did not paste")

    # C2 — First free block (1pm-2pm)
    if _has_time_block(draft_content, 13, 0, 14, 0):
        score += CRITERION_POINTS["C2_first_block"]
        subscores["C2"] = CRITERION_POINTS["C2_first_block"]
        feedback.append("C2 PASS: 1pm-2pm free block mentioned (Personal+Family computation)")
    else:
        subscores["C2"] = 0
        feedback.append("C2 FAIL: 1pm-2pm free block not detected — agent may have included Work calendar")

    # C3 — Last free block (4:30pm-5pm)
    if _has_time_block(draft_content, 16, 30, 17, 0):
        score += CRITERION_POINTS["C3_last_block"]
        subscores["C3"] = CRITERION_POINTS["C3_last_block"]
        feedback.append("C3 PASS: 4:30pm-5pm free block mentioned")
    else:
        subscores["C3"] = 0
        feedback.append("C3 FAIL: 4:30pm-5pm free block not detected")

    # C4 — Excludes Work events and tentative yoga
    trap_hits = []
    for pat in WORK_EVENT_TRAPS:
        if pat.search(draft_content):
            trap_hits.append(pat.pattern)
    if TENTATIVE_TRAP.search(draft_content):
        trap_hits.append("yoga (tentative)")
    if not trap_hits:
        score += CRITERION_POINTS["C4_excludes_traps"]
        subscores["C4"] = CRITERION_POINTS["C4_excludes_traps"]
        feedback.append("C4 PASS: no Work-calendar or tentative-event traps in draft")
    else:
        subscores["C4"] = 0
        feedback.append(f"C4 FAIL: trap content present in draft ({', '.join(trap_hits)})")

    # C5 — Raycast WAL changed
    if wal_changed:
        score += CRITERION_POINTS["C5_raycast_touched"]
        subscores["C5"] = CRITERION_POINTS["C5_raycast_touched"]
        feedback.append("C5 PASS: Raycast settings DB modified after setup")
    else:
        subscores["C5"] = 0
        feedback.append("C5 FAIL: Raycast settings DB not modified — agent may not have used Raycast")

    passed = score >= PASS_THRESHOLD

    return {
        "passed":    passed,
        "score":     score,
        "feedback":  " | ".join(feedback),
        "subscores": subscores,
    }
