#!/usr/bin/env python3
"""
Verifier for correct_mounting_plate_rev_b task.

The agent must apply Engineering Change Order ECO-2024-0856, correcting 3 wrong
dimensional constraints in a mounting plate CAD file while preserving 3 correct ones.

REV-A (wrong) → REV-B (correct):
  120mm → 160mm  (overall plate width)
   75mm → 100mm  (overall plate height)
   35mm →  50mm  (top-right corner step)

Correct constraints to preserve:
   40mm  (corner cutout vertical depth)
  110mm  (inner horizontal edge)
   60mm  (left edge height)

Scoring (total = 100):
  - 20 pts: plate_rev_b.slvs exists and was saved after task start
  - 13 pts: correct 160mm width present (±0.5mm)
  - 13 pts: correct 100mm height present (±0.5mm)
  - 13 pts: correct  50mm step present (±0.5mm)
  -  7 pts: correct  40mm cutout preserved (±0.5mm)
  -  7 pts: correct 110mm inner edge preserved (±0.5mm)
  -  7 pts: correct  60mm left height preserved (±0.5mm)
  -  7 pts: wrong 120mm removed
  -  7 pts: wrong  75mm removed
  -  6 pts: wrong  35mm removed

Pass threshold: 80 / 100
"""

import json
import tempfile
import os

RESULT_PATH = "/tmp/correct_mounting_plate_rev_b_result.json"
TOL = 0.5


def verify_correct_mounting_plate_rev_b(traj, env_info, task_info):
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
                "feedback": "FAIL: plate_rev_b.slvs was not saved."}
    if not result.get('output_file_is_new', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: plate_rev_b.slvs not modified after task start (stale)."}
    score += 20
    feedback.append("PASS (+20): plate_rev_b.slvs saved correctly.")

    constraints = result.get('constraints', [])
    dist_cs = [c for c in constraints if c.get('type') == 30]

    def has_val(v, tol=TOL):
        return any(abs(c.get('valA', -9999) - v) <= tol for c in dist_cs)

    # ── Correct values that MUST now be present ──
    correct_new = [
        (160.0, 13, "160mm overall plate width (REV-B)"),
        (100.0, 13, "100mm overall plate height (REV-B)"),
        (50.0,  13, "50mm top-right corner step (REV-B)"),
    ]
    for target, pts, label in correct_new:
        if has_val(target):
            score += pts
            feedback.append(f"PASS (+{pts}): {label} found.")
        else:
            vals = sorted(c.get('valA', 0) for c in dist_cs)
            feedback.append(f"FAIL (+0): {label} ({target}mm) NOT found. Present: {vals}")

    # ── Correct values that must be PRESERVED ──
    correct_keep = [
        (40.0,  7, "40mm corner cutout depth (preserved)"),
        (110.0, 7, "110mm inner horizontal edge (preserved)"),
        (60.0,  7, "60mm left edge height (preserved)"),
    ]
    for target, pts, label in correct_keep:
        if has_val(target):
            score += pts
            feedback.append(f"PASS (+{pts}): {label} ({target}mm) still present.")
        else:
            vals = sorted(c.get('valA', 0) for c in dist_cs)
            feedback.append(f"FAIL (+0): {label} ({target}mm) missing — was it accidentally removed?")

    # ── Wrong REV-A values that must be REMOVED ──
    wrong_revA = [
        (120.0, 7, "wrong REV-A 120mm width"),
        (75.0,  7, "wrong REV-A 75mm height"),
        (35.0,  6, "wrong REV-A 35mm step"),
    ]
    for wrong_val, pts, label in wrong_revA:
        if not has_val(wrong_val):
            score += pts
            feedback.append(f"PASS (+{pts}): {label} removed.")
        else:
            feedback.append(f"FAIL (+0): {label} ({wrong_val}mm) still present — must be removed.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": "\n".join(feedback)
    }
