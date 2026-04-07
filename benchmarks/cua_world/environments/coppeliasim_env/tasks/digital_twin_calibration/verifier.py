#!/usr/bin/env python3
"""
Verifier for Digital Twin Calibration: Full Kinematic & Dynamic Robot Characterization.

This is a stub verifier. Full evaluation is performed externally via the
VLM checklist verifier, which assesses agent trajectory screenshots and
exported file contents against a structured rubric.

The stub performs basic structural validation of the result JSON produced
by export_result.sh to provide a coarse programmatic score.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/digital_twin_calibration_result.json"


def verify_digital_twin_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()

    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export script did not run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result data: {e}"}
    finally:
        if os.path.exists(tmp.name):
            try:
                os.unlink(tmp.name)
            except Exception:
                pass

    score = 0
    feedback = []

    if result.get("error"):
        feedback.append(f"Export script error: {result['error']}")

    # 1. Kinematic survey CSV (20 pts)
    kin_exists = result.get("kin_csv_exists") and result.get("kin_csv_is_new")
    kin_rows = result.get("kin_csv_rows", 0)
    if kin_exists and kin_rows >= 65:
        score += 20
        feedback.append(f"Kinematic CSV: {kin_rows} rows (+20)")
    elif kin_exists and kin_rows >= 20:
        score += 10
        feedback.append(f"Kinematic CSV: {kin_rows} rows (partial +10)")
    elif kin_exists:
        score += 5
        feedback.append(f"Kinematic CSV exists but only {kin_rows} rows (+5)")
    else:
        feedback.append("Kinematic CSV missing or stale")

    # 2. Dynamic excitation CSV (20 pts)
    dyn_exists = result.get("dyn_csv_exists") and result.get("dyn_csv_is_new")
    dyn_rows = result.get("dyn_csv_rows", 0)
    dyn_joints = result.get("dyn_csv_distinct_joints", 0)
    dyn_torque = result.get("dyn_csv_has_nonzero_torque", False)
    if dyn_exists and dyn_rows >= 600 and dyn_joints >= 6 and dyn_torque:
        score += 20
        feedback.append(f"Dynamic CSV: {dyn_rows} rows, {dyn_joints} joints, torques present (+20)")
    elif dyn_exists and dyn_rows >= 100:
        score += 10
        feedback.append(f"Dynamic CSV: {dyn_rows} rows, {dyn_joints} joints (partial +10)")
    elif dyn_exists:
        score += 5
        feedback.append(f"Dynamic CSV exists but only {dyn_rows} rows (+5)")
    else:
        feedback.append("Dynamic CSV missing or stale")

    # 3. Identified parameters JSON (20 pts)
    par_exists = result.get("par_json_exists") and result.get("par_json_is_new")
    par_count = result.get("par_json_joint_count", 0)
    par_inertia = result.get("par_json_all_inertia_positive", False)
    par_r2 = result.get("par_json_all_r2_valid", False)
    if par_exists and par_count >= 6 and par_inertia and par_r2:
        score += 20
        feedback.append(f"Parameters JSON: {par_count} joints, valid inertia and R2 (+20)")
    elif par_exists and par_count >= 6:
        score += 10
        feedback.append(f"Parameters JSON: {par_count} joints but inertia/R2 issues (partial +10)")
    elif par_exists:
        score += 5
        feedback.append(f"Parameters JSON exists but only {par_count} joints (+5)")
    else:
        feedback.append("Parameters JSON missing or stale")

    # 4. Validation results CSV (20 pts)
    val_exists = result.get("val_csv_exists") and result.get("val_csv_is_new")
    val_rows = result.get("val_csv_rows", 0)
    val_pred_meas = result.get("val_csv_has_pred_and_meas", False)
    if val_exists and val_rows >= 100 and val_pred_meas:
        score += 20
        feedback.append(f"Validation CSV: {val_rows} rows with pred+meas columns (+20)")
    elif val_exists and val_rows >= 20:
        score += 10
        feedback.append(f"Validation CSV: {val_rows} rows (partial +10)")
    elif val_exists:
        score += 5
        feedback.append(f"Validation CSV exists but only {val_rows} rows (+5)")
    else:
        feedback.append("Validation CSV missing or stale")

    # 5. Characterization report JSON (20 pts)
    rep_exists = result.get("rep_json_exists") and result.get("rep_json_is_new")
    rep_kin = result.get("rep_json_has_kinematic", False)
    rep_dyn = result.get("rep_json_has_dynamic", False)
    rep_val = result.get("rep_json_has_validation", False)
    if rep_exists and rep_kin and rep_dyn and rep_val:
        score += 20
        feedback.append("Report JSON: all 3 sections present (+20)")
    elif rep_exists and (rep_kin or rep_dyn or rep_val):
        sections = sum([rep_kin, rep_dyn, rep_val])
        pts = sections * 5
        score += pts
        feedback.append(f"Report JSON: {sections}/3 sections (partial +{pts})")
    elif rep_exists:
        score += 5
        feedback.append("Report JSON exists but missing required sections (+5)")
    else:
        feedback.append("Report JSON missing or stale")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
