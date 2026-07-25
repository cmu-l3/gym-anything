"""Verifier for raycast_screenshot_ocr_clipboard.

Scoring (100 pts, pass >= 70):
  C1 — Apple Note 'Equipment Inventory' contains 'REF-9X4Q-22847'         30 pts
        (the correct serial from the target LG fridge screenshot)
  C2 — Note does NOT contain any distractor serial                        15 pts
        (WMC-5512-B82, DRY-7741-N09, TV-2293-OLED, SPK-7711-A2, MIC-3309-K1)
  C3 — Note does NOT contain 'WTY-8X4' nor any other 'WTY-' code          15 pts
        (agent must copy ONLY the serial, not the warranty claim line)
  C4 — Final system clipboard equals 'call mom after 6'                   25 pts
        (agent must RESTORE original clipboard after pasting)
  C5 — Raycast WAL changed (agent actually used Raycast for OCR search)   15 pts
"""

import json
import os
import re
import tempfile

PASS_THRESHOLD = 70

CRITERION_POINTS = {
    "C1_correct_serial":   30,
    "C2_no_distractors":   15,
    "C3_no_warranty_code": 15,
    "C4_clipboard_restored": 25,
    "C5_raycast_touched":  15,
}

CORRECT_SERIAL = "REF-9X4Q-22847"
DISTRACTOR_SERIALS = [
    "WMC-5512-B82", "DRY-7741-N09", "TV-2293-OLED",
    "SPK-7711-A2",  "MIC-3309-K1",
]
WARRANTY_CODE_RE = re.compile(r"\bWTY-[A-Z0-9]{2,5}\b", re.IGNORECASE)


def verify_screenshot_ocr_clipboard(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/raycast_screenshot_ocr_clipboard_result.json"
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

    note_plain = result.get("note_body_plain", "") or ""
    clipboard_final = (result.get("final_clipboard") or "").strip()
    wal_changed = result.get("raycast_wal_changed_after_setup", False)

    # C1 — correct serial in note
    if CORRECT_SERIAL in note_plain:
        score += CRITERION_POINTS["C1_correct_serial"]
        subscores["C1"] = CRITERION_POINTS["C1_correct_serial"]
        feedback.append(f"C1 PASS: correct serial '{CORRECT_SERIAL}' in note")
    else:
        subscores["C1"] = 0
        feedback.append(f"C1 FAIL: correct serial '{CORRECT_SERIAL}' missing from note")

    # C2 — no distractor serials
    found_distractors = [d for d in DISTRACTOR_SERIALS if d in note_plain]
    if not found_distractors:
        score += CRITERION_POINTS["C2_no_distractors"]
        subscores["C2"] = CRITERION_POINTS["C2_no_distractors"]
        feedback.append("C2 PASS: no distractor serials in note")
    else:
        subscores["C2"] = 0
        feedback.append(f"C2 FAIL: distractor serial(s) in note: {found_distractors}")

    # C3 — no WTY-* warranty code
    wty_hits = WARRANTY_CODE_RE.findall(note_plain)
    if not wty_hits:
        score += CRITERION_POINTS["C3_no_warranty_code"]
        subscores["C3"] = CRITERION_POINTS["C3_no_warranty_code"]
        feedback.append("C3 PASS: no WTY-* warranty code in note (agent copied serial only)")
    else:
        subscores["C3"] = 0
        feedback.append(f"C3 FAIL: WTY-* code(s) in note ({wty_hits}) — agent copied too much")

    # C4 — clipboard restored
    if clipboard_final == "call mom after 6":
        score += CRITERION_POINTS["C4_clipboard_restored"]
        subscores["C4"] = CRITERION_POINTS["C4_clipboard_restored"]
        feedback.append("C4 PASS: clipboard restored to 'call mom after 6'")
    else:
        subscores["C4"] = 0
        feedback.append(
            f"C4 FAIL: clipboard not restored (current: {clipboard_final!r})"
        )

    # C5 — Raycast WAL changed
    if wal_changed:
        score += CRITERION_POINTS["C5_raycast_touched"]
        subscores["C5"] = CRITERION_POINTS["C5_raycast_touched"]
        feedback.append("C5 PASS: Raycast was used (WAL changed)")
    else:
        subscores["C5"] = 0
        feedback.append("C5 FAIL: Raycast WAL unchanged (agent may have bypassed Raycast)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed":    passed,
        "score":     score,
        "feedback":  " | ".join(feedback),
        "subscores": subscores,
    }
