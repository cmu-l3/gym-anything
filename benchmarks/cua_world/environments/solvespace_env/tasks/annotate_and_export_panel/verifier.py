#!/usr/bin/env python3
"""
Verifier for annotate_and_export_panel task.

Scoring (total = 100):
  - 15 pts: divider_annotated.slvs saved and is new after task start
  - 10 pts: at least 3 new PT_PT_DISTANCE constraints added vs baseline
  - 15 pts: 150mm overall width constraint present (±1mm)
  - 15 pts: 100mm overall height constraint present (±1mm)
  - 15 pts: 25mm notch depth constraint present (±1mm)
  - 30 pts: divider_shop_drawing.dxf exported, is new, and is valid DXF format

Score=0 if neither file was saved.
"""

import json
import tempfile
import os

RESULT_PATH = "/tmp/annotate_and_export_panel_result.json"
TOL = 1.0  # mm tolerance (more generous for this task with real files)


def verify_annotate_and_export_panel(traj, env_info, task_info):
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

    # Must save at least one of the two files
    slvs_new = result.get('slvs_is_new', False)
    dxf_new = result.get('dxf_is_new', False)
    if not slvs_new and not dxf_new:
        return {"passed": False, "score": 0,
                "feedback": "FAIL: Neither divider_annotated.slvs nor divider_shop_drawing.dxf was saved."}

    # ── Check 1: .slvs file ──
    if slvs_new:
        score += 15
        feedback.append("PASS (+15): divider_annotated.slvs saved.")
    else:
        feedback.append("FAIL (+0): divider_annotated.slvs not saved as new file.")

    # ── Check 2: new constraints added ──
    new_count = result.get('new_constraint_count', 0)
    if new_count >= 3:
        score += 10
        feedback.append(f"PASS (+10): {new_count} new constraints added.")
    else:
        feedback.append(f"FAIL (+0): Only {new_count} new constraints (need ≥3).")

    # ── Check 3-5: specific dimension values ──
    dist_cs = result.get('dist_constraints', [])

    def has_val(v):
        return any(abs(c.get('valA', -9999) - v) <= TOL for c in dist_cs)

    for val, label in [(150.0, "150mm overall width"), (100.0, "100mm overall height"),
                       (25.0, "25mm notch depth")]:
        if has_val(val):
            score += 15
            feedback.append(f"PASS (+15): {label} constraint found.")
        else:
            vals = sorted([c.get('valA', 0) for c in dist_cs])
            feedback.append(f"FAIL (+0): {label} constraint not found. Present values: {vals}")

    # ── Check 6: DXF export ──
    if dxf_new and result.get('dxf_valid', False) and result.get('dxf_size', 0) > 100:
        score += 30
        feedback.append(f"PASS (+30): divider_shop_drawing.dxf exported ({result['dxf_size']} bytes, valid DXF).")
    elif dxf_new:
        score += 15
        feedback.append("PARTIAL (+15): DXF file saved but may not be valid.")
    else:
        feedback.append("FAIL (+0): divider_shop_drawing.dxf not exported.")

    return {"passed": score >= 70, "score": score, "feedback": "\n".join(feedback)}
