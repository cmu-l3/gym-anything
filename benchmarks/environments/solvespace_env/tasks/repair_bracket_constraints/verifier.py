#!/usr/bin/env python3
"""
Verifier for repair_bracket_constraints task.

Scoring (total = 100):
  - 20 pts: output file bracket_constrained.slvs exists and was created after task start
  - 20 pts: file contains at least 3 new PT_PT_DISTANCE (type=30) constraints
  - 20 pts: 85mm horizontal arm length constraint present (±0.5mm)
  - 20 pts: 60mm vertical arm height constraint present (±0.5mm)
  - 20 pts: 10mm arm thickness constraint present (±0.5mm)

Score=0 immediately if file does not exist or was not modified after task start.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/repair_bracket_constraints_result.json"
TOL = 0.5  # mm tolerance for dimension matching


def verify_repair_bracket_constraints(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    tol = metadata.get('constraint_tolerance_mm', TOL)

    # Copy result JSON from VM
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env(RESULT_PATH, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file from VM: {e}"
        }
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    feedback = []
    score = 0

    # ── Check 1: file exists and is new ──
    if not result.get('output_file_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: bracket_constrained.slvs was not saved. Agent did not complete the task."
        }
    if not result.get('output_file_is_new', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: bracket_constrained.slvs exists but was not modified after task start (stale file)."
        }
    score += 20
    feedback.append("PASS (+20): bracket_constrained.slvs saved correctly.")

    # ── Check 2: At least 3 PT_PT_DISTANCE constraints present ──
    constraints = result.get('constraints', [])
    dist_constraints = [c for c in constraints if c.get('type') == 30]
    if len(dist_constraints) < 3:
        feedback.append(f"FAIL (+0): Found only {len(dist_constraints)} PT_PT_DISTANCE constraints (need ≥3).")
    else:
        score += 20
        feedback.append(f"PASS (+20): Found {len(dist_constraints)} PT_PT_DISTANCE constraints.")

    # ── Helper: check if a value is present among constraints ──
    def has_value(target_val, constraints_list, tolerance):
        return any(abs(c.get('valA', -999) - target_val) <= tolerance
                   for c in constraints_list)

    # ── Check 3: 85mm horizontal arm length ──
    if has_value(85.0, dist_constraints, tol):
        score += 20
        feedback.append("PASS (+20): 85mm horizontal arm length constraint found.")
    else:
        vals = sorted([c.get('valA', 0) for c in dist_constraints])
        feedback.append(f"FAIL (+0): 85mm constraint not found. Present distance values: {vals}")

    # ── Check 4: 60mm vertical arm height ──
    if has_value(60.0, dist_constraints, tol):
        score += 20
        feedback.append("PASS (+20): 60mm vertical arm height constraint found.")
    else:
        vals = sorted([c.get('valA', 0) for c in dist_constraints])
        feedback.append(f"FAIL (+0): 60mm constraint not found. Present distance values: {vals}")

    # ── Check 5: 10mm arm thickness ──
    if has_value(10.0, dist_constraints, tol):
        score += 20
        feedback.append("PASS (+20): 10mm arm thickness constraint found.")
    else:
        vals = sorted([c.get('valA', 0) for c in dist_constraints])
        feedback.append(f"FAIL (+0): 10mm constraint not found. Present distance values: {vals}")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
