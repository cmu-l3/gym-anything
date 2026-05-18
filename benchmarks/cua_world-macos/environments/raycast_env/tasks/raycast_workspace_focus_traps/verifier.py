"""Verifier for raycast_workspace_focus_traps.

Scoring (100 pts, pass >= 70):
  C1 — Safari frontmost                                                    10 pts
  C2 — Safari window on LEFT HALF of screen                                15 pts
  C3 — Some Preview window on RIGHT HALF                                   15 pts
        AND its title contains 'lease-renewal' (not lease-old)
  C4 — lease-old.pdf Preview window has NOT moved (frame matches initial   20 pts
        within tolerance — focus-trap test)
  C5 — Notes window in BOTTOM-RIGHT QUARTER                                10 pts
  C6 — Mail is minimized (at least one Mail window AXMinimized=true)       10 pts
  C7 — Raycast window exists                                               10 pts
  C8 — Finder NOT visible on current Space (moved to next Space)           10 pts

Position tolerance: 15% of screen dimensions.
"""

import json
import os
import re
import tempfile

PASS_THRESHOLD = 70

CRITERION_POINTS = {
    "C1_safari_front":         10,
    "C2_safari_left_half":     15,
    "C3_preview_right_half":   15,
    "C4_lease_old_untouched":  20,
    "C5_notes_br_quarter":     10,
    "C6_mail_minimized":       10,
    "C7_raycast_present":      10,
    "C8_finder_off_space":     10,
}

FRAME_TOL_PX = 30


def _frame_close(a, b, tol_px=FRAME_TOL_PX):
    """Two frames are 'untouched-close' if each component differs by < tol_px."""
    if not a or not b or len(a) != 4 or len(b) != 4:
        return False
    return all(abs(a[i] - b[i]) <= tol_px for i in range(4))


def _center_near(win, screen, target_cx, target_cy, tol_x=0.15, tol_y=0.20):
    """Check if window centre is within tol fractions of the target centre."""
    if not screen or len(screen) != 4 or not win:
        return False
    sw, sh = screen[2], screen[3]
    if sw <= 0 or sh <= 0:
        return False
    cx_frac = (win["x"] + win["w"] / 2) / sw
    cy_frac = (win["y"] + win["h"] / 2) / sh
    return abs(cx_frac - target_cx) <= tol_x and abs(cy_frac - target_cy) <= tol_y


def _is_left_half(win, screen):
    # Ideal centre: x=0.25, y=0.5. Window must occupy ~left half.
    return _center_near(win, screen, 0.25, 0.5, tol_x=0.15, tol_y=0.35)


def _is_right_half(win, screen):
    return _center_near(win, screen, 0.75, 0.5, tol_x=0.15, tol_y=0.35)


def _is_bottom_right_quarter(win, screen):
    return _center_near(win, screen, 0.75, 0.75, tol_x=0.15, tol_y=0.15)


def _find_window_by_title(wins, needle):
    needle = needle.lower()
    for w in wins:
        if needle in (w.get("title") or "").lower():
            return w
    return None


def verify_workspace_focus_traps(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/raycast_workspace_focus_traps_result.json"
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

    front_app = result.get("frontmost_app", "") or ""
    screen    = result.get("screen_bounds")
    lease_old_initial = result.get("lease_old_initial_frame")
    safari_wins  = result.get("safari_windows", []) or []
    preview_wins = result.get("preview_windows", []) or []
    notes_wins   = result.get("notes_windows", []) or []
    mail_wins    = result.get("mail_windows", []) or []
    finder_vis   = result.get("finder_visible_current_space", True)
    raycast_wins = result.get("raycast_windows", []) or []

    # C1 — Safari frontmost
    if front_app.strip().lower() == "safari":
        score += CRITERION_POINTS["C1_safari_front"]
        subscores["C1"] = CRITERION_POINTS["C1_safari_front"]
        feedback.append("C1 PASS: Safari is frontmost")
    else:
        subscores["C1"] = 0
        feedback.append(f"C1 FAIL: frontmost is {front_app!r}, expected Safari")

    # C2 — Safari on left half
    safari_front = safari_wins[0] if safari_wins else None
    if safari_front and _is_left_half(safari_front, screen):
        score += CRITERION_POINTS["C2_safari_left_half"]
        subscores["C2"] = CRITERION_POINTS["C2_safari_left_half"]
        feedback.append("C2 PASS: Safari on left half")
    else:
        subscores["C2"] = 0
        feedback.append("C2 FAIL: Safari not on left half (or no Safari window)")

    # C3 — Preview window for lease-renewal on right half
    renewal_win = _find_window_by_title(preview_wins, "lease-renewal")
    if renewal_win and _is_right_half(renewal_win, screen):
        score += CRITERION_POINTS["C3_preview_right_half"]
        subscores["C3"] = CRITERION_POINTS["C3_preview_right_half"]
        feedback.append("C3 PASS: lease-renewal Preview on right half")
    else:
        subscores["C3"] = 0
        if not renewal_win:
            feedback.append("C3 FAIL: no Preview window titled 'lease-renewal'")
        else:
            feedback.append("C3 FAIL: lease-renewal Preview not on right half")

    # C4 — lease-old.pdf untouched
    old_win = _find_window_by_title(preview_wins, "lease-old")
    if old_win and lease_old_initial:
        cur_frame = [old_win["x"], old_win["y"], old_win["w"], old_win["h"]]
        if _frame_close(cur_frame, lease_old_initial):
            score += CRITERION_POINTS["C4_lease_old_untouched"]
            subscores["C4"] = CRITERION_POINTS["C4_lease_old_untouched"]
            feedback.append("C4 PASS: lease-old Preview window left untouched")
        else:
            subscores["C4"] = 0
            feedback.append(
                f"C4 FAIL: lease-old window moved (initial={lease_old_initial}, "
                f"current={cur_frame})"
            )
    else:
        subscores["C4"] = 0
        feedback.append("C4 FAIL: cannot find lease-old Preview window or initial frame")

    # C5 — Notes in bottom-right quarter
    notes_front = notes_wins[0] if notes_wins else None
    if notes_front and _is_bottom_right_quarter(notes_front, screen):
        score += CRITERION_POINTS["C5_notes_br_quarter"]
        subscores["C5"] = CRITERION_POINTS["C5_notes_br_quarter"]
        feedback.append("C5 PASS: Notes in bottom-right quarter")
    else:
        subscores["C5"] = 0
        feedback.append("C5 FAIL: Notes not in bottom-right quarter")

    # C6 — Mail minimized
    mail_minimized = any(w.get("minimized") for w in mail_wins) if mail_wins else False
    if mail_minimized:
        score += CRITERION_POINTS["C6_mail_minimized"]
        subscores["C6"] = CRITERION_POINTS["C6_mail_minimized"]
        feedback.append("C6 PASS: Mail is minimized")
    else:
        subscores["C6"] = 0
        feedback.append("C6 FAIL: no Mail window is minimized")

    # C7 — Raycast window exists (AI Chat or Notes etc.)
    if raycast_wins:
        score += CRITERION_POINTS["C7_raycast_present"]
        subscores["C7"] = CRITERION_POINTS["C7_raycast_present"]
        feedback.append(f"C7 PASS: Raycast window present ({len(raycast_wins)} window(s))")
    else:
        subscores["C7"] = 0
        feedback.append("C7 FAIL: no Raycast window present")

    # C8 — Finder not on current Space (best-effort)
    if not finder_vis:
        score += CRITERION_POINTS["C8_finder_off_space"]
        subscores["C8"] = CRITERION_POINTS["C8_finder_off_space"]
        feedback.append("C8 PASS: Finder appears off current Space")
    else:
        subscores["C8"] = 0
        feedback.append("C8 FAIL: Finder still visible on current Space")

    passed = score >= PASS_THRESHOLD

    return {
        "passed":    passed,
        "score":     score,
        "feedback":  " | ".join(feedback),
        "subscores": subscores,
    }
