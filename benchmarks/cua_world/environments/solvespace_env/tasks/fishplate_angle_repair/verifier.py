#!/usr/bin/env python3
"""
Verifier for fishplate_angle_repair task.

A railway engineer must correct 2 wrong distance constraints and 1 wrong angle
constraint on a fishplate cross-section profile, then save and export DXF.

Scoring (total = 100):
  - 20 pts: fishplate_corrected.slvs exists and was saved after task start
  - 20 pts: width constraint = 160 mm (±0.5 mm)
  - 20 pts: height constraint = 22 mm (±0.5 mm)
  - 15 pts: angle constraint = 30 degrees (±0.5 deg)  [type=110]
  - 25 pts: fishplate_corrected.dxf exists and was created after task start

Pass threshold: 86.
Anti-Pattern-4 check: max score without angle = 20+20+20+25 = 85 < 86. ✓
DXF gate: if DXF missing and score >= 86, cap to 85.
Score=0 immediately if .slvs not created or not new.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/fishplate_angle_repair_result.json"
TOL_MM  = 0.5
TOL_DEG = 0.5
PASS_THRESHOLD = 86

CORRECT_WIDTH  = 160.0
CORRECT_HEIGHT =  22.0
CORRECT_ANGLE  =  30.0


def verify_fishplate_angle_repair(traj, env_info, task_info):
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

    # Gate: .slvs must exist and be new
    if not result.get('slvs_exists', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: fishplate_corrected.slvs was not saved."}
    if not result.get('slvs_is_new', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: fishplate_corrected.slvs was not modified after task start."}
    score += 20
    feedback.append("PASS (+20): fishplate_corrected.slvs saved correctly.")

    constraints = result.get('constraints', [])
    dist   = [c for c in constraints if c.get('type') == 30]
    angles = [c for c in constraints if c.get('type') == 110]

    def has_dist(target):
        return any(abs(c.get('valA', -9999) - target) <= TOL_MM for c in dist)

    def has_angle(target):
        return any(abs(c.get('valA', -9999) - target) <= TOL_DEG for c in angles)

    # Check width
    if has_dist(CORRECT_WIDTH):
        score += 20
        feedback.append("PASS (+20): 160 mm width constraint found.")
    else:
        vals = sorted(c.get('valA', 0) for c in dist)
        feedback.append(f"FAIL (+0): 160 mm width not found. Distance values: {vals}")

    # Check height
    if has_dist(CORRECT_HEIGHT):
        score += 20
        feedback.append("PASS (+20): 22 mm height constraint found.")
    else:
        vals = sorted(c.get('valA', 0) for c in dist)
        feedback.append(f"FAIL (+0): 22 mm height not found. Distance values: {vals}")

    # Check angle
    if has_angle(CORRECT_ANGLE):
        score += 15
        feedback.append("PASS (+15): 30° angle constraint found.")
    else:
        avals = sorted(c.get('valA', 0) for c in angles)
        feedback.append(f"FAIL (+0): 30° angle not found. Angle values: {avals}")

    # DXF gate
    dxf_new = result.get('dxf_is_new', False)
    dxf_exists = result.get('dxf_exists', False)
    if dxf_new:
        score += 25
        feedback.append("PASS (+25): fishplate_corrected.dxf exported successfully.")
    else:
        feedback.append(f"FAIL (+0): fishplate_corrected.dxf not exported (exists={dxf_exists}).")
        if score >= PASS_THRESHOLD:
            score = PASS_THRESHOLD - 1
            feedback.append(f"NOTE: Score capped to {PASS_THRESHOLD - 1} — DXF export is required.")

    passed = score >= PASS_THRESHOLD
    return {"passed": passed, "score": score, "feedback": "\n".join(feedback)}
