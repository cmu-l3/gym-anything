#!/usr/bin/env python3
"""
Verifier for sensor_housing_from_spec task.

An instrumentation engineer must create a stepped-rectangle sensor housing
cross-section from scratch per a spec sheet, applying 5 dimension constraints,
saving the .slvs file and exporting a DXF.

Scoring (total = 100):
  - 10 pts: sensor_housing.slvs exists and was saved after task start
  - 15 pts: body width constraint = 96 mm (±0.5 mm)
  - 15 pts: body height constraint = 48 mm (±0.5 mm)
  - 15 pts: boss width constraint = 48 mm (±0.5 mm)
  - 15 pts: boss height constraint = 32 mm (±0.5 mm)
  - 10 pts: left boss offset constraint = 24 mm (±0.5 mm)
  - 20 pts: sensor_housing.dxf exists and was created after task start

Pass threshold: 75. DXF gate: if DXF missing and score >= 75, cap to 74.
Score=0 immediately if .slvs not created or not new.

Note: body_width=96 and boss_width=48 are distinct (48 != 96) so they are
distinguishable in the constraint list. However, body_height=48 and boss_width=48
share the same value — both must be present, so we require count >= 2 for value 48.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/sensor_housing_from_spec_result.json"
TOL = 0.5
PASS_THRESHOLD = 75

BODY_W    =  96.0
BODY_H    =  48.0
BOSS_W    =  48.0
BOSS_H    =  32.0
BOSS_OFF  =  24.0


def verify_sensor_housing_from_spec(traj, env_info, task_info):
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
                "feedback": "FAIL: sensor_housing.slvs was not saved."}
    if not result.get('slvs_is_new', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: sensor_housing.slvs was not modified after task start."}
    score += 10
    feedback.append("PASS (+10): sensor_housing.slvs saved correctly.")

    constraints = result.get('constraints', [])
    dist = [c for c in constraints if c.get('type') == 30]
    vals = [c.get('valA', -9999) for c in dist]

    def count_near(target):
        return sum(1 for v in vals if abs(v - target) <= TOL)

    def has_value(target):
        return count_near(target) >= 1

    # 96mm body width
    if has_value(BODY_W):
        score += 15
        feedback.append("PASS (+15): 96 mm body width constraint found.")
    else:
        feedback.append(f"FAIL (+0): 96 mm body width not found. Constraint values: {sorted(vals)}")

    # 48mm appears twice (body_height=48 AND boss_width=48)
    count_48 = count_near(BODY_H)  # BODY_H == BOSS_W == 48
    if count_48 >= 2:
        score += 15 + 15  # both body_height and boss_width
        feedback.append("PASS (+30): Both 48 mm body height and 48 mm boss width constraints found.")
    elif count_48 == 1:
        score += 15
        feedback.append(f"PARTIAL (+15): Only one 48 mm constraint found (need 2 — body height AND boss width).")
    else:
        feedback.append(f"FAIL (+0): 48 mm constraint(s) not found. Constraint values: {sorted(vals)}")

    # 32mm boss height
    if has_value(BOSS_H):
        score += 15
        feedback.append("PASS (+15): 32 mm boss height constraint found.")
    else:
        feedback.append(f"FAIL (+0): 32 mm boss height not found. Constraint values: {sorted(vals)}")

    # 24mm boss left offset
    if has_value(BOSS_OFF):
        score += 10
        feedback.append("PASS (+10): 24 mm left boss offset constraint found.")
    else:
        feedback.append(f"FAIL (+0): 24 mm left offset not found. Constraint values: {sorted(vals)}")

    dxf_new = result.get('dxf_is_new', False)
    dxf_exists = result.get('dxf_exists', False)
    if dxf_new:
        score += 20
        feedback.append("PASS (+20): sensor_housing.dxf exported successfully.")
    else:
        feedback.append(f"FAIL (+0): sensor_housing.dxf not exported (exists={dxf_exists}).")
        if score >= PASS_THRESHOLD:
            score = PASS_THRESHOLD - 1
            feedback.append(f"NOTE: Score capped to {PASS_THRESHOLD - 1} — DXF export is required.")

    passed = score >= PASS_THRESHOLD
    return {"passed": passed, "score": score, "feedback": "\n".join(feedback)}
