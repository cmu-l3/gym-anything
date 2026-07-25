"""Verifier for raycast_screenshot_ocr_aichat.

Scoring (100 pts, pass >= 70):
  C1 — Apple Note 'Packages' exists                                        15 pts
  C2 — Note contains target tracking '1Z-9X4-2284-7AB'                     30 pts
  C3 — Note contains 'UPS' (correct carrier)                               10 pts
  C4 — Note does NOT contain distractor tracking numbers                   15 pts
        (TBA-3490-0911-43 or 9405-5111-2345-6789)
  C5 — Note does NOT contain '2240 SE Yamhill' (REI shipping address)      15 pts
  C6 — Note does NOT contain '8821' (Newegg card fragment)                 10 pts
  C7 — Raycast WAL changed                                                  5 pts
"""

import json
import os
import tempfile

PASS_THRESHOLD = 70

CRITERION_POINTS = {
    "C1_note_exists":      15,
    "C2_target_tracking":  30,
    "C3_correct_carrier":  10,
    "C4_no_distractors":   15,
    "C5_no_address":       15,
    "C6_no_card":          10,
    "C7_raycast_touched":   5,
}

TARGET_TRACKING = "1Z-9X4-2284-7AB"
DISTRACTORS = ["TBA-3490-0911-43", "9405-5111-2345-6789"]


def verify_screenshot_ocr_aichat(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/raycast_screenshot_ocr_aichat_result.json"
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

    plain = result.get("note_body_plain", "") or ""
    plain_l = plain.lower()
    wal_changed = result.get("raycast_wal_changed_after_setup", False)

    # C1
    if result.get("note_exists"):
        score += CRITERION_POINTS["C1_note_exists"]
        subscores["C1"] = CRITERION_POINTS["C1_note_exists"]
        feedback.append("C1 PASS: 'Packages' note exists")
    else:
        subscores["C1"] = 0
        feedback.append("C1 FAIL: 'Packages' note missing")

    # C2 — target tracking
    if TARGET_TRACKING in plain:
        score += CRITERION_POINTS["C2_target_tracking"]
        subscores["C2"] = CRITERION_POINTS["C2_target_tracking"]
        feedback.append(f"C2 PASS: target tracking '{TARGET_TRACKING}' present")
    else:
        subscores["C2"] = 0
        feedback.append(f"C2 FAIL: target tracking '{TARGET_TRACKING}' missing")

    # C3 — UPS carrier
    if "ups" in plain_l:
        score += CRITERION_POINTS["C3_correct_carrier"]
        subscores["C3"] = CRITERION_POINTS["C3_correct_carrier"]
        feedback.append("C3 PASS: 'UPS' carrier name present")
    else:
        subscores["C3"] = 0
        feedback.append("C3 FAIL: 'UPS' carrier name missing")

    # C4 — no distractor trackings
    hits = [d for d in DISTRACTORS if d in plain]
    if not hits:
        score += CRITERION_POINTS["C4_no_distractors"]
        subscores["C4"] = CRITERION_POINTS["C4_no_distractors"]
        feedback.append("C4 PASS: no distractor tracking numbers")
    else:
        subscores["C4"] = 0
        feedback.append(f"C4 FAIL: distractor tracking(s) in note: {hits}")

    # C5 — no address
    if "2240 se yamhill" not in plain_l:
        score += CRITERION_POINTS["C5_no_address"]
        subscores["C5"] = CRITERION_POINTS["C5_no_address"]
        feedback.append("C5 PASS: shipping address fragment not in note")
    else:
        subscores["C5"] = 0
        feedback.append("C5 FAIL: REI shipping address '2240 SE Yamhill' leaked into note")

    # C6 — no card
    if "8821" not in plain:
        score += CRITERION_POINTS["C6_no_card"]
        subscores["C6"] = CRITERION_POINTS["C6_no_card"]
        feedback.append("C6 PASS: card last-4 '8821' not in note")
    else:
        subscores["C6"] = 0
        feedback.append("C6 FAIL: card last-4 '8821' leaked into note")

    # C7 — Raycast WAL
    if wal_changed:
        score += CRITERION_POINTS["C7_raycast_touched"]
        subscores["C7"] = CRITERION_POINTS["C7_raycast_touched"]
        feedback.append("C7 PASS: Raycast WAL changed")
    else:
        subscores["C7"] = 0
        feedback.append("C7 FAIL: Raycast WAL unchanged")

    passed = score >= PASS_THRESHOLD

    return {
        "passed":    passed,
        "score":     score,
        "feedback":  " | ".join(feedback),
        "subscores": subscores,
    }
