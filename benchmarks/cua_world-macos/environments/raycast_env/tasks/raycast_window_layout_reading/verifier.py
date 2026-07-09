"""Verifier for raycast_window_layout_reading.

Scoring (100 pts, pass >= 70):
  C1 — Safari is running                                            15 pts
  C2 — Notes is running                                             15 pts
  C3 — Safari front tab URL contains 'ycombinator.com'              25 pts
  C4 — Safari window occupies LEFT HALF of screen                   25 pts
        (left edge <= 15% of screen width AND
         right edge between 40% and 65% of screen width)
  C5 — Notes window occupies RIGHT HALF of screen                   20 pts
        (left edge between 35% and 60% of screen width AND
         right edge >= 85% of screen width)

Position checks use a tolerance band so the agent doesn't need
pixel-perfect placement.

Do-nothing: nothing running -> 0.
"""

import json
import os
import tempfile

PASS_THRESHOLD = 70

CRITERION_POINTS = {
    "C1_safari_running": 15,
    "C2_notes_running":  15,
    "C3_safari_url":     25,
    "C4_safari_left":    25,
    "C5_notes_right":    20,
}

# Position tolerance (fraction of screen width)
LEFT_HALF_LEFT_MAX   = 0.15  # left edge must be within 15% of screen-left
LEFT_HALF_RIGHT_MIN  = 0.40  # right edge must be at least 40% of screen-width
LEFT_HALF_RIGHT_MAX  = 0.65  # right edge must be at most 65% of screen-width

RIGHT_HALF_LEFT_MIN  = 0.35  # left edge must be at least 35% of screen-width
RIGHT_HALF_LEFT_MAX  = 0.60  # left edge must be at most 60% of screen-width
RIGHT_HALF_RIGHT_MIN = 0.85  # right edge must be at least 85% of screen-width


def _is_left_half(frame, screen):
    if not frame or not screen or len(frame) != 4 or len(screen) != 4:
        return False, "missing frame/screen data"
    x, y, w, h = frame
    sw = screen[2]
    if sw <= 0:
        return False, "invalid screen width"
    left_pct  = x / sw
    right_pct = (x + w) / sw
    ok = (left_pct <= LEFT_HALF_LEFT_MAX
          and LEFT_HALF_RIGHT_MIN <= right_pct <= LEFT_HALF_RIGHT_MAX)
    return ok, f"left_pct={left_pct:.2f} right_pct={right_pct:.2f}"


def _is_right_half(frame, screen):
    if not frame or not screen or len(frame) != 4 or len(screen) != 4:
        return False, "missing frame/screen data"
    x, y, w, h = frame
    sw = screen[2]
    if sw <= 0:
        return False, "invalid screen width"
    left_pct  = x / sw
    right_pct = (x + w) / sw
    ok = (RIGHT_HALF_LEFT_MIN <= left_pct <= RIGHT_HALF_LEFT_MAX
          and right_pct >= RIGHT_HALF_RIGHT_MIN)
    return ok, f"left_pct={left_pct:.2f} right_pct={right_pct:.2f}"


def verify_window_layout_reading(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/raycast_window_layout_reading_result.json"
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

    safari_running = result.get("safari_running", False)
    notes_running  = result.get("notes_running", False)
    safari_url     = result.get("safari_url", "") or ""
    safari_frame   = result.get("safari_frame")
    notes_frame    = result.get("notes_frame")
    screen         = result.get("screen_bounds")

    # C1
    if safari_running:
        score += CRITERION_POINTS["C1_safari_running"]
        subscores["C1"] = CRITERION_POINTS["C1_safari_running"]
        feedback.append("C1 PASS: Safari is running")
    else:
        subscores["C1"] = 0
        feedback.append("C1 FAIL: Safari is not running")

    # C2
    if notes_running:
        score += CRITERION_POINTS["C2_notes_running"]
        subscores["C2"] = CRITERION_POINTS["C2_notes_running"]
        feedback.append("C2 PASS: Notes is running")
    else:
        subscores["C2"] = 0
        feedback.append("C2 FAIL: Notes is not running")

    # C3
    if "ycombinator.com" in safari_url.lower():
        score += CRITERION_POINTS["C3_safari_url"]
        subscores["C3"] = CRITERION_POINTS["C3_safari_url"]
        feedback.append(f"C3 PASS: Safari URL contains ycombinator.com ({safari_url[:60]})")
    else:
        subscores["C3"] = 0
        feedback.append(f"C3 FAIL: Safari URL does not contain ycombinator.com (got: {safari_url[:60]!r})")

    # C4 — Safari on left half
    ok4, detail4 = _is_left_half(safari_frame, screen)
    if ok4:
        score += CRITERION_POINTS["C4_safari_left"]
        subscores["C4"] = CRITERION_POINTS["C4_safari_left"]
        feedback.append(f"C4 PASS: Safari window on left half ({detail4})")
    else:
        subscores["C4"] = 0
        feedback.append(f"C4 FAIL: Safari not on left half — {detail4}")

    # C5 — Notes on right half
    ok5, detail5 = _is_right_half(notes_frame, screen)
    if ok5:
        score += CRITERION_POINTS["C5_notes_right"]
        subscores["C5"] = CRITERION_POINTS["C5_notes_right"]
        feedback.append(f"C5 PASS: Notes window on right half ({detail5})")
    else:
        subscores["C5"] = 0
        feedback.append(f"C5 FAIL: Notes not on right half — {detail5}")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
