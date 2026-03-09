#!/usr/bin/env python3
"""
Verifier for extrude_constrained_profile task.

Scoring (total = 100):
  - 25 pts: profile_extruded.slvs exists and was created after task start
  - 50 pts: file contains a Group.type=5100 (extrude group) — core task requirement
  - 25 pts: extrude depth constraint ~100mm present (±1mm), OR any new PT_PT_DISTANCE
            in the extrude group context (~100mm) is present

Score=0 if file does not exist or was not created after task start.
"""

import json
import tempfile
import os

RESULT_PATH = "/tmp/extrude_constrained_profile_result.json"
EXTRUDE_GROUP_TYPE = 5100
DEPTH_MM = 100.0
DEPTH_TOL = 1.0


def verify_extrude_constrained_profile(traj, env_info, task_info):
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
                "feedback": "FAIL: profile_extruded.slvs not saved."}
    if not result.get('output_file_is_new', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: profile_extruded.slvs not modified after task start."}

    score += 25
    feedback.append("PASS (+25): profile_extruded.slvs saved.")

    parse_result = result.get('parse_result', {})
    group_types = parse_result.get('group_types', [])

    if EXTRUDE_GROUP_TYPE in group_types:
        score += 50
        feedback.append("PASS (+50): Extrude group (type=5100) found — 3D extrusion created.")
    else:
        feedback.append(f"FAIL (+0): No extrude group (type=5100) found. Group types present: {group_types}")

    # Check for depth constraint (~100mm)
    dist_cs = parse_result.get('dist_constraints', [])
    has_depth = any(abs(c.get('valA', -9999) - DEPTH_MM) <= DEPTH_TOL for c in dist_cs)
    if has_depth:
        score += 25
        feedback.append("PASS (+25): 100mm extrude depth constraint found.")
    else:
        all_vals = sorted([c.get('valA', 0) for c in dist_cs
                           if c.get('valA', 0) > 50])  # only large values
        feedback.append(f"PARTIAL: 100mm depth constraint not found. Large constraints: {all_vals}. "
                        "Note: in SolveSpace, extrude depth may be set as a sketch constraint on the extrude group.")

    return {"passed": score >= 75, "score": score, "feedback": "\n".join(feedback)}
