#!/usr/bin/env python3
"""
Verifier for trailer_coupler_full_pipeline task.

A trailer manufacturing engineer must:
  1. Draw a U-channel cross-section from scratch on the XY plane
  2. Apply 5 dimension constraints per spec
  3. Extrude the profile into a 3D solid (Group.type=5100 required)
  4. Save as coupler_beam.slvs
  5. Export DXF to coupler_beam.dxf

Scoring (total = 100):
  - 10 pts: coupler_beam.slvs exists and was saved after task start
  - 12 pts: overall width constraint = 180 mm (±0.5 mm)
  - 12 pts: web height constraint = 120 mm (±0.5 mm)
  - 12 pts: flange width constraint = 20 mm (±0.5 mm)
  - 12 pts: wall thickness constraint = 12 mm (±0.5 mm)
  - 12 pts: inner width constraint = 140 mm (±0.5 mm)
  - 20 pts: extrude group (Group.type=5100) present in .slvs
  - 10 pts: coupler_beam.dxf exists and was created after task start

Pass threshold: 75.
DXF gate: if DXF missing and score >= 75, cap to 74.
Extrude gate: if no extrude group and score >= 75, cap to 74.
Score=0 immediately if .slvs not created or not new.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/trailer_coupler_full_pipeline_result.json"
TOL = 0.5
PASS_THRESHOLD = 75

OVERALL_W  = 180.0
WEB_H      = 120.0
FLANGE_W   =  20.0
WALL_T     =  12.0
INNER_W    = 140.0


def verify_trailer_coupler_full_pipeline(traj, env_info, task_info):
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
                "feedback": "FAIL: coupler_beam.slvs was not saved."}
    if not result.get('slvs_is_new', False):
        return {"passed": False, "score": 0,
                "feedback": "FAIL: coupler_beam.slvs was not modified after task start."}
    score += 10
    feedback.append("PASS (+10): coupler_beam.slvs saved correctly.")

    constraints = result.get('constraints', [])
    dist = [c for c in constraints if c.get('type') == 30]
    vals = [c.get('valA', -9999) for c in dist]

    def has_value(target):
        return any(abs(v - target) <= TOL for v in vals)

    # Note: WALL_T=12 and FLANGE_W=20 differ enough; INNER_W=140 unique
    checks = [
        (OVERALL_W, 12, "overall width (180 mm)"),
        (WEB_H,     12, "web height (120 mm)"),
        (FLANGE_W,  12, "flange width (20 mm)"),
        (WALL_T,    12, "wall thickness (12 mm)"),
        (INNER_W,   12, "inner width (140 mm)"),
    ]
    for target, pts, label in checks:
        if has_value(target):
            score += pts
            feedback.append(f"PASS (+{pts}): {label} constraint found.")
        else:
            feedback.append(f"FAIL (+0): {label} not found. Constraint values: {sorted(vals)}")

    # Extrude group check
    has_extrude = result.get('has_extrude_group', False)
    if has_extrude:
        score += 20
        feedback.append("PASS (+20): Extrude group (Group.type=5100) found — 3D solid created.")
    else:
        feedback.append("FAIL (+0): No extrude group found — sketch was not extruded into a 3D solid.")

    # DXF check
    dxf_new = result.get('dxf_is_new', False)
    dxf_exists = result.get('dxf_exists', False)
    if dxf_new:
        score += 10
        feedback.append("PASS (+10): coupler_beam.dxf exported successfully.")
    else:
        feedback.append(f"FAIL (+0): coupler_beam.dxf not exported (exists={dxf_exists}).")

    # Hard gates: extrude AND dxf are both required to pass
    if not has_extrude and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback.append(f"NOTE: Score capped to {PASS_THRESHOLD - 1} — extrusion is required to pass.")
    if not dxf_new and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback.append(f"NOTE: Score capped to {PASS_THRESHOLD - 1} — DXF export is required.")

    passed = score >= PASS_THRESHOLD
    return {"passed": passed, "score": score, "feedback": "\n".join(feedback)}
