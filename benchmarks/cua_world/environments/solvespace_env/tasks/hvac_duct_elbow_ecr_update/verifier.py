#!/usr/bin/env python3
"""
Verifier for hvac_duct_elbow_ecr_update task.

An HVAC engineer must update 4 parametric dimension constraints in a duct elbow
cross-section per an ECR document, then save and export DXF.

Scoring (total = 100):
  - 15 pts: duct_elbow_updated.slvs exists and was saved after task start
  - 15 pts: total width constraint = 300 mm (±0.5 mm)
  - 15 pts: total height constraint = 240 mm (±0.5 mm)
  - 15 pts: leg height constraint = 130 mm (±0.5 mm)
  - 15 pts: wall thickness constraint = 70 mm (±0.5 mm)
  - 25 pts: duct_elbow_updated.dxf exists and was created after task start

Pass threshold: 75. DXF gate: if DXF missing and score >= 75, cap to 74.
Score=0 immediately if .slvs not created or not new.

Anti-gaming: old values (250, 200, 100, 50) must NOT be present — if the old value
for a dimension is found instead of the new one, that dimension scores 0.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/hvac_duct_elbow_ecr_update_result.json"
TOL = 0.5
PASS_THRESHOLD = 75

# ECR target values (new)
NEW_TOTAL_W = 300.0
NEW_TOTAL_H = 240.0
NEW_LEG_H   = 130.0
NEW_WALL_T  =  70.0

# Old values (should NOT appear as the dimension value)
OLD_TOTAL_W = 250.0
OLD_TOTAL_H = 200.0
OLD_LEG_H   = 100.0
OLD_WALL_T  =  50.0


def verify_hvac_duct_elbow_ecr_update(traj, env_info, task_info):
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

    if not result.get('slvs_exists', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: duct_elbow_updated.slvs was not saved."}
    if not result.get('slvs_is_new', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: duct_elbow_updated.slvs was not modified after task start."}
    score += 15
    feedback.append("PASS (+15): duct_elbow_updated.slvs saved correctly.")

    constraints = result.get('constraints', [])
    dist = [c for c in constraints if c.get('type') == 30]

    def has_value(target):
        return any(abs(c.get('valA', -9999) - target) <= TOL for c in dist)

    def all_vals():
        return sorted(c.get('valA', 0) for c in dist)

    checks = [
        (NEW_TOTAL_W, OLD_TOTAL_W, 15, "total width (300 mm)"),
        (NEW_TOTAL_H, OLD_TOTAL_H, 15, "total height (240 mm)"),
        (NEW_LEG_H,   OLD_LEG_H,   15, "leg height (130 mm)"),
        (NEW_WALL_T,  OLD_WALL_T,   15, "wall thickness (70 mm)"),
    ]
    for new_val, old_val, pts, label in checks:
        if has_value(new_val):
            score += pts
            feedback.append(f"PASS (+{pts}): {label} constraint found.")
        elif has_value(old_val):
            feedback.append(f"FAIL (+0): {label} — old value ({old_val}) still present, not updated.")
        else:
            feedback.append(f"FAIL (+0): {label} not found. Present values: {all_vals()}")

    dxf_new = result.get('dxf_is_new', False)
    dxf_exists = result.get('dxf_exists', False)
    if dxf_new:
        score += 25
        feedback.append("PASS (+25): duct_elbow_updated.dxf exported successfully.")
    else:
        feedback.append(f"FAIL (+0): duct_elbow_updated.dxf not exported (exists={dxf_exists}).")
        if score >= PASS_THRESHOLD:
            score = PASS_THRESHOLD - 1
            feedback.append(f"NOTE: Score capped to {PASS_THRESHOLD - 1} — DXF export is required.")

    passed = score >= PASS_THRESHOLD
    return {"passed": passed, "score": score, "feedback": "\n".join(feedback)}
