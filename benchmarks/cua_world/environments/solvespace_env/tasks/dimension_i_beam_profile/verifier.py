#!/usr/bin/env python3
"""
Verifier for dimension_i_beam_profile task.

The agent must add 8 PT_PT_DISTANCE constraints to an asymmetric I-beam
cross-section profile, reading the required values from the structural
specification on the desktop.

Scoring (total = 100):
  - 20 pts: i_beam_constrained.slvs exists and was saved after task start
  - 10 pts: at least 8 PT_PT_DISTANCE (type=30) constraints present
  - 10 pts: 120mm overall flange width
  - 10 pts:  90mm overall section height
  - 10 pts:  12mm bottom flange thickness
  - 10 pts:  18mm top flange thickness
  - 10 pts:  40mm right flange overhang
  - 10 pts:  30mm left flange overhang
  -  5 pts:  60mm web clear height
  -  5 pts:  50mm web thickness

Pass threshold: 80 / 100
"""

import json
import tempfile
import os

RESULT_PATH = "/tmp/dimension_i_beam_profile_result.json"
TOL = 0.5  # mm


def verify_dimension_i_beam_profile(traj, env_info, task_info):
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
                "feedback": "FAIL: i_beam_constrained.slvs was not saved."}
    if not result.get('output_file_is_new', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: i_beam_constrained.slvs not modified after task start (stale)."}
    score += 20
    feedback.append("PASS (+20): i_beam_constrained.slvs saved correctly.")

    constraints = result.get('constraints', [])
    dist_cs = [c for c in constraints if c.get('type') == 30]

    def has_val(target, tol=TOL):
        return any(abs(c.get('valA', -9999) - target) <= tol for c in dist_cs)

    # ── Check 2: minimum constraint count ──
    if len(dist_cs) >= 8:
        score += 10
        feedback.append(f"PASS (+10): {len(dist_cs)} PT_PT_DISTANCE constraints found (≥8 required).")
    else:
        feedback.append(f"FAIL (+0): Only {len(dist_cs)} PT_PT_DISTANCE constraints found (need ≥8).")

    # ── Checks 3-10: specific dimension values ──
    checks = [
        (120.0, 10, "120mm overall flange width"),
        (90.0,  10, "90mm overall section height"),
        (12.0,  10, "12mm bottom flange thickness"),
        (18.0,  10, "18mm top flange thickness"),
        (40.0,  10, "40mm right flange overhang"),
        (30.0,  10, "30mm left flange overhang"),
        (60.0,   5, "60mm web clear height"),
        (50.0,   5, "50mm web thickness"),
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
