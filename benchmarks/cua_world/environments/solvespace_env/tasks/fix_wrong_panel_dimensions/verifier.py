#!/usr/bin/env python3
"""
Verifier for fix_wrong_panel_dimensions task.

Scoring (total = 100):
  - 20 pts: panel_corrected.slvs exists and was created after task start
  - 20 pts: no constraint with wrong width value (95mm) remains
  - 20 pts: no constraint with wrong height value (50mm) remains
  - 20 pts: correct width 120mm is present (±0.5mm)
  - 20 pts: correct height 75mm is present (±0.5mm)

Score=0 if file does not exist or was not created after task start.
"""

import json
import tempfile
import os

RESULT_PATH = "/tmp/fix_wrong_panel_dimensions_result.json"
TOL = 0.5
WRONG_WIDTH = 95.0
WRONG_HEIGHT = 50.0
CORRECT_WIDTH = 120.0
CORRECT_HEIGHT = 75.0


def verify_fix_wrong_panel_dimensions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')

    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env(RESULT_PATH, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    feedback = []
    score = 0

    if not result.get('output_file_exists', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: panel_corrected.slvs not saved."}
    if not result.get('output_file_is_new', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: panel_corrected.slvs not modified after task start."}

    score += 20
    feedback.append("PASS (+20): panel_corrected.slvs saved.")

    constraints = result.get('constraints', [])
    dist_cs = [c for c in constraints if c.get('type') == 30]

    def has_val(v):
        return any(abs(c.get('valA', -9999) - v) <= TOL for c in dist_cs)

    # Check wrong values are GONE
    if not has_val(WRONG_WIDTH):
        score += 20
        feedback.append("PASS (+20): Wrong 95mm width constraint removed.")
    else:
        feedback.append("FAIL (+0): Wrong 95mm width constraint still present.")

    if not has_val(WRONG_HEIGHT):
        score += 20
        feedback.append("PASS (+20): Wrong 50mm height constraint removed.")
    else:
        feedback.append("FAIL (+0): Wrong 50mm height constraint still present.")

    # Check correct values are present
    if has_val(CORRECT_WIDTH):
        score += 20
        feedback.append("PASS (+20): Correct 120mm width constraint present.")
    else:
        vals = sorted([c.get('valA', 0) for c in dist_cs])
        feedback.append(f"FAIL (+0): 120mm width constraint not found. Present: {vals}")

    if has_val(CORRECT_HEIGHT):
        score += 20
        feedback.append("PASS (+20): Correct 75mm height constraint present.")
    else:
        vals = sorted([c.get('valA', 0) for c in dist_cs])
        feedback.append(f"FAIL (+0): 75mm height constraint not found. Present: {vals}")

    return {"passed": score >= 80, "score": score, "feedback": "\n".join(feedback)}
