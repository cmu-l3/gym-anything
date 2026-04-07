#!/usr/bin/env python3
"""
Verifier for constrain_stiffener_rib_dims task.

The agent must apply 6 PT_PT_DISTANCE constraints to a web stiffener rib
(stepped gusset plate) cross-section based on the fabrication drawing.

Required dimensions:
  130mm  overall base length
   25mm  bottom ledge height
   30mm  ledge horizontal depth (notch step)
   45mm  web height above ledge
  100mm  top edge length
   70mm  total plate height

Scoring (total = 100):
  - 20 pts: stiffener_constrained.slvs exists and was saved after task start
  - 10 pts: at least 6 PT_PT_DISTANCE (type=30) constraints present
  - 12 pts: 130mm overall base
  - 12 pts:  25mm bottom ledge height
  - 12 pts:  30mm ledge depth (notch)
  - 12 pts:  45mm web height above ledge
  - 11 pts: 100mm top edge length
  - 11 pts:  70mm total plate height

Pass threshold: 80 / 100
"""

import json
import tempfile
import os

RESULT_PATH = "/tmp/constrain_stiffener_rib_dims_result.json"
TOL = 0.5


def verify_constrain_stiffener_rib_dims(traj, env_info, task_info):
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
                "feedback": "FAIL: stiffener_constrained.slvs was not saved."}
    if not result.get('output_file_is_new', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: stiffener_constrained.slvs not modified after task start (stale)."}
    score += 20
    feedback.append("PASS (+20): stiffener_constrained.slvs saved correctly.")

    constraints = result.get('constraints', [])
    dist_cs = [c for c in constraints if c.get('type') == 30]

    def has_val(target, tol=TOL):
        return any(abs(c.get('valA', -9999) - target) <= tol for c in dist_cs)

    # ── Check 2: minimum constraint count ──
    if len(dist_cs) >= 6:
        score += 10
        feedback.append(f"PASS (+10): {len(dist_cs)} PT_PT_DISTANCE constraints found (≥6 required).")
    else:
        feedback.append(f"FAIL (+0): Only {len(dist_cs)} PT_PT_DISTANCE constraints found (need ≥6).")

    # ── Checks 3-8: specific dimension values ──
    checks = [
        (130.0, 12, "130mm overall base length"),
        (25.0,  12, "25mm bottom ledge height"),
        (30.0,  12, "30mm ledge horizontal depth"),
        (45.0,  12, "45mm web height above ledge"),
        (100.0, 11, "100mm top edge length"),
        (70.0,  11, "70mm total plate height"),
    ]
    for target, pts, label in checks:
        if has_val(target):
            score += pts
            feedback.append(f"PASS (+{pts}): {label} constraint found.")
        else:
            vals = sorted(c.get('valA', 0) for c in dist_cs)
            feedback.append(f"FAIL (+0): {label} ({target}mm) NOT found. Present values: {vals}")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": "\n".join(feedback)
    }
