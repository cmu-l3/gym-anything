#!/usr/bin/env python3
"""
Verifier for constrain_rectangular_frame task.

Scoring (total = 100):
  - 20 pts: gasket_frame_constrained.slvs exists and was created after task start
  - 20 pts: at least 4 PT_PT_DISTANCE constraints present
  - 15 pts: 200mm outer width constraint present (±0.5mm)
  - 15 pts: 150mm outer height constraint present (±0.5mm)
  - 15 pts: 180mm inner width constraint present (±0.5mm)
  - 15 pts: 130mm inner height constraint present (±0.5mm)
"""

import json
import tempfile
import os

RESULT_PATH = "/tmp/constrain_rectangular_frame_result.json"
TOL = 0.5


def verify_constrain_rectangular_frame(traj, env_info, task_info):
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
                "feedback": "FAIL: gasket_frame_constrained.slvs not saved."}
    if not result.get('output_file_is_new', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: gasket_frame_constrained.slvs not modified after task start."}

    score += 20
    feedback.append("PASS (+20): gasket_frame_constrained.slvs saved.")

    constraints = result.get('constraints', [])
    dist_cs = [c for c in constraints if c.get('type') == 30]

    if len(dist_cs) >= 4:
        score += 20
        feedback.append(f"PASS (+20): {len(dist_cs)} PT_PT_DISTANCE constraints found.")
    else:
        feedback.append(f"FAIL (+0): Only {len(dist_cs)} PT_PT_DISTANCE constraints (need ≥4).")

    def has_val(v):
        return any(abs(c.get('valA', -9999) - v) <= TOL for c in dist_cs)

    checks = [(200.0, "outer width 200mm"), (150.0, "outer height 150mm"),
              (180.0, "inner width 180mm"), (130.0, "inner height 130mm")]

    for val, label in checks:
        if has_val(val):
            score += 15
            feedback.append(f"PASS (+15): {label} constraint found.")
        else:
            vals = sorted([c.get('valA', 0) for c in dist_cs])
            feedback.append(f"FAIL (+0): {label} constraint not found. Present values: {vals}")

    return {"passed": score >= 80, "score": score, "feedback": "\n".join(feedback)}
