#!/usr/bin/env python3
"""
Verifier for constrain_u_channel_profile task.

The agent must apply 5 PT_PT_DISTANCE constraints to a U-channel (press die)
cross-section profile based on the tooling design specification.

Required dimensions:
  120mm  overall channel width
   70mm  leg height (outer)
   15mm  wall thickness
   55mm  inner clear depth
   90mm  inner clear width (base)

Scoring (total = 100):
  - 20 pts: u_channel_constrained.slvs exists and was saved after task start
  - 10 pts: at least 5 PT_PT_DISTANCE (type=30) constraints present
  - 14 pts: 120mm overall channel width
  - 14 pts:  70mm leg height
  - 14 pts:  15mm wall thickness
  - 14 pts:  55mm inner clear depth
  - 14 pts:  90mm inner clear width

Pass threshold: 80 / 100
"""

import json
import tempfile
import os

RESULT_PATH = "/tmp/constrain_u_channel_profile_result.json"
TOL = 0.5


def verify_constrain_u_channel_profile(traj, env_info, task_info):
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
                "feedback": "FAIL: u_channel_constrained.slvs was not saved."}
    if not result.get('output_file_is_new', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: u_channel_constrained.slvs not modified after task start (stale)."}
    score += 20
    feedback.append("PASS (+20): u_channel_constrained.slvs saved correctly.")

    constraints = result.get('constraints', [])
    dist_cs = [c for c in constraints if c.get('type') == 30]

    def has_val(target, tol=TOL):
        return any(abs(c.get('valA', -9999) - target) <= tol for c in dist_cs)

    # ── Check 2: minimum constraint count ──
    if len(dist_cs) >= 5:
        score += 10
        feedback.append(f"PASS (+10): {len(dist_cs)} PT_PT_DISTANCE constraints found (≥5 required).")
    else:
        feedback.append(f"FAIL (+0): Only {len(dist_cs)} PT_PT_DISTANCE constraints found (need ≥5).")

    # ── Checks 3-7: specific dimension values ──
    checks = [
        (120.0, 14, "120mm overall channel width"),
        (70.0,  14, "70mm leg height (outer)"),
        (15.0,  14, "15mm wall thickness"),
        (55.0,  14, "55mm inner clear depth"),
        (90.0,  14, "90mm inner clear width"),
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
