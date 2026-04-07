#!/usr/bin/env python3
"""
Verifier for fix_channel_section_errors task.

The agent must identify and correct 3 wrong dimensional constraints in a
C-channel cross-section, leaving the 2 correct constraints untouched.

Wrong → Correct:
  65mm → 83mm  (outer wall / section height)
  25mm → 18mm  (flange thickness)
  32mm → 47mm  (web inner height)

Correct constraints to preserve:
  100mm  (bottom width)
   80mm  (inner flange clear width)

Scoring (total = 100):
  - 20 pts: channel_corrected.slvs exists and was saved after task start
  - 10 pts: correct 83mm outer wall height present (±0.5mm)
  - 10 pts: correct 18mm flange thickness present (±0.5mm)
  - 10 pts: correct 47mm web inner height present (±0.5mm)
  - 10 pts: correct 100mm bottom width preserved (±0.5mm)
  - 10 pts: correct  80mm inner width preserved (±0.5mm)
  - 10 pts: wrong 65mm removed (not present in corrected file)
  - 10 pts: wrong 25mm removed (not present in corrected file)
  - 10 pts: wrong 32mm removed (not present in corrected file)

Pass threshold: 80 / 100
"""

import json
import tempfile
import os

RESULT_PATH = "/tmp/fix_channel_section_errors_result.json"
TOL = 0.5


def verify_fix_channel_section_errors(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')

    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env(RESULT_PATH, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file from VM: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    feedback = []
    score = 0

    # ── Check 1: file exists and is new ──
    if not result.get('output_file_exists', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: channel_corrected.slvs was not saved."}
    if not result.get('output_file_is_new', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: channel_corrected.slvs not modified after task start (stale)."}
    score += 20
    feedback.append("PASS (+20): channel_corrected.slvs saved correctly.")

    constraints = result.get('constraints', [])
    dist_cs = [c for c in constraints if c.get('type') == 30]

    def has_val(v, tol=TOL):
        return any(abs(c.get('valA', -9999) - v) <= tol for c in dist_cs)

    # ── Checks: correct values present ──
    correct_checks = [
        (83.0, 10, "83mm section outer height"),
        (18.0, 10, "18mm flange thickness"),
        (47.0, 10, "47mm web inner height"),
        (100.0, 10, "100mm bottom width (preserved)"),
        (80.0,  10, "80mm inner flange width (preserved)"),
    ]
    for target, pts, label in correct_checks:
        if has_val(target):
            score += pts
            feedback.append(f"PASS (+{pts}): {label} ({target}mm) found.")
        else:
            vals = sorted(c.get('valA', 0) for c in dist_cs)
            feedback.append(f"FAIL (+0): {label} ({target}mm) NOT found. Present: {vals}")

    # ── Checks: wrong values removed ──
    wrong_checks = [
        (65.0, 10, "wrong 65mm outer wall height"),
        (25.0, 10, "wrong 25mm flange thickness"),
        (32.0, 10, "wrong 32mm web inner height"),
    ]
    for wrong_val, pts, label in wrong_checks:
        if not has_val(wrong_val):
            score += pts
            feedback.append(f"PASS (+{pts}): {label} removed from file.")
        else:
            feedback.append(f"FAIL (+0): {label} ({wrong_val}mm) still present — must be removed.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": "\n".join(feedback)
    }
