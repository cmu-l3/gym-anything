#!/usr/bin/env python3
"""
Verifier for pipe_support_flange_repair task.

A piping engineer must correct 5 wrong distance constraints on a T-flange profile
and export both a corrected .slvs and a .dxf file.

Scoring (total = 100):
  - 15 pts: flange_corrected.slvs exists and was saved after task start
  - 12 pts: base width constraint = 120 mm (±0.5 mm)
  - 12 pts: base height constraint = 12 mm (±0.5 mm)
  - 12 pts: hub width constraint = 36 mm (±0.5 mm)
  - 12 pts: hub height constraint = 60 mm (±0.5 mm)
  - 12 pts: left offset constraint = 42 mm (±0.5 mm)
  - 25 pts: flange_corrected.dxf exists and was created after task start

Pass threshold: 75. DXF gate: if dxf not present and score >= 75, cap score to 74.
Score=0 immediately if .slvs was not created or is not new.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/pipe_support_flange_repair_result.json"
TOL = 0.5
PASS_THRESHOLD = 75

# Correct values (Rev C spec)
CORRECT_BASE_W    = 120.0
CORRECT_BASE_H    =  12.0
CORRECT_HUB_W     =  36.0
CORRECT_HUB_H     =  60.0
CORRECT_LEFT_OFF  =  42.0


def verify_pipe_support_flange_repair(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    tol = metadata.get('constraint_tolerance_mm', TOL)

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
                "feedback": "FAIL: flange_corrected.slvs was not saved."}
    if not result.get('slvs_is_new', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: flange_corrected.slvs exists but was not modified after task start."}
    score += 15
    feedback.append("PASS (+15): flange_corrected.slvs saved correctly.")

    constraints = result.get('constraints', [])
    dist = [c for c in constraints if c.get('type') == 30]

    def has_value(target):
        return any(abs(c.get('valA', -9999) - target) <= tol for c in dist)

    def all_vals():
        return sorted(c.get('valA', 0) for c in dist)

    # Check each of the 5 dimensions
    checks = [
        (CORRECT_BASE_W,   12, "base width (120 mm)"),
        (CORRECT_BASE_H,   12, "base height (12 mm)"),
        (CORRECT_HUB_W,    12, "hub width (36 mm)"),
        (CORRECT_HUB_H,    12, "hub height (60 mm)"),
        (CORRECT_LEFT_OFF, 12, "left offset (42 mm)"),
    ]
    for target, pts, label in checks:
        if has_value(target):
            score += pts
            feedback.append(f"PASS (+{pts}): {label} constraint found.")
        else:
            feedback.append(f"FAIL (+0): {label} constraint not found. Present values: {all_vals()}")

    # DXF gate
    dxf_new = result.get('dxf_is_new', False)
    dxf_exists = result.get('dxf_exists', False)
    if dxf_new:
        score += 25
        feedback.append("PASS (+25): flange_corrected.dxf exported successfully.")
    else:
        feedback.append(f"FAIL (+0): flange_corrected.dxf not exported (exists={dxf_exists}).")
        if score >= PASS_THRESHOLD:
            score = PASS_THRESHOLD - 1
            feedback.append(f"NOTE: Score capped to {PASS_THRESHOLD - 1} — DXF export is required to pass.")

    passed = score >= PASS_THRESHOLD
    return {"passed": passed, "score": score, "feedback": "\n".join(feedback)}
