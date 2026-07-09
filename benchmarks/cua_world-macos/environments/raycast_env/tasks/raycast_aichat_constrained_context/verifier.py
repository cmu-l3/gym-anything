"""Verifier for raycast_aichat_constrained_context.

Scoring (100 pts, pass >= 70):
  C1 — Existing 'Packing constraints' note still exists (not deleted)      15 pts
  C2 — Note has grown — agent appended content                             20 pts
  C3 — Note contains the '## Conflict check' heading                       25 pts
  C4 — Note also retains the original 'Packing constraints' content        15 pts
        (agent appended, did not overwrite)
  C5 — No NEW Apple Note titled 'Trip conflict check' or                   10 pts
        'Conflict check' was created (agent appended to existing,
        did not create a new note)
  C6 — Raycast WAL changed (Raycast AI Chat was used)                      15 pts
"""

import json
import os
import re
import tempfile

PASS_THRESHOLD = 70

CRITERION_POINTS = {
    "C1_note_exists":      15,
    "C2_note_grew":        20,
    "C3_heading_present":  25,
    "C4_original_kept":    15,
    "C5_no_new_note":      10,
    "C6_raycast_touched":  15,
}

HEADING_RE = re.compile(r"##\s*Conflict\s*check", re.IGNORECASE)
ORIGINAL_KEYWORDS = ["18L", "rain shell", "Cooper", "Battery pack", "vet appointment"]


def verify_aichat_constrained_context(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/raycast_aichat_constrained_context_result.json"
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

    note_plain    = result.get("note_body_plain", "") or ""
    note_raw      = result.get("note_body_raw", "") or ""
    note_grew     = result.get("note_grew", False)
    new_note_count = result.get("new_note_count", 0)
    wal_changed   = result.get("raycast_wal_changed_after_setup", False)

    # C1
    if note_raw:
        score += CRITERION_POINTS["C1_note_exists"]
        subscores["C1"] = CRITERION_POINTS["C1_note_exists"]
        feedback.append("C1 PASS: 'Packing constraints' note exists")
    else:
        subscores["C1"] = 0
        feedback.append("C1 FAIL: 'Packing constraints' note missing/deleted")

    # C2
    if note_grew:
        score += CRITERION_POINTS["C2_note_grew"]
        subscores["C2"] = CRITERION_POINTS["C2_note_grew"]
        feedback.append("C2 PASS: note body grew (content appended)")
    else:
        subscores["C2"] = 0
        feedback.append("C2 FAIL: note body did not grow")

    # C3 — heading present
    if HEADING_RE.search(note_plain):
        score += CRITERION_POINTS["C3_heading_present"]
        subscores["C3"] = CRITERION_POINTS["C3_heading_present"]
        feedback.append("C3 PASS: '## Conflict check' heading present in note")
    else:
        subscores["C3"] = 0
        feedback.append("C3 FAIL: '## Conflict check' heading not found")

    # C4 — original content retained
    retained = [k for k in ORIGINAL_KEYWORDS if k.lower() in note_plain.lower()]
    if len(retained) >= 3:
        score += CRITERION_POINTS["C4_original_kept"]
        subscores["C4"] = CRITERION_POINTS["C4_original_kept"]
        feedback.append(f"C4 PASS: original note content retained ({len(retained)}/5 keywords)")
    else:
        subscores["C4"] = 0
        feedback.append(f"C4 FAIL: original content lost — only {len(retained)}/5 keywords kept")

    # C5 — no new note
    if new_note_count == 0:
        score += CRITERION_POINTS["C5_no_new_note"]
        subscores["C5"] = CRITERION_POINTS["C5_no_new_note"]
        feedback.append("C5 PASS: no new 'Trip conflict' note created (agent appended)")
    else:
        subscores["C5"] = 0
        feedback.append(f"C5 FAIL: {new_note_count} new note(s) with conflict-related title")

    # C6
    if wal_changed:
        score += CRITERION_POINTS["C6_raycast_touched"]
        subscores["C6"] = CRITERION_POINTS["C6_raycast_touched"]
        feedback.append("C6 PASS: Raycast WAL changed")
    else:
        subscores["C6"] = 0
        feedback.append("C6 FAIL: Raycast WAL unchanged")

    passed = score >= PASS_THRESHOLD

    return {
        "passed":    passed,
        "score":     score,
        "feedback":  " | ".join(feedback),
        "subscores": subscores,
    }
