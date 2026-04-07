#!/usr/bin/env python3
"""
Verifier for constellation_plane_phasing@1

The agent must construct a multi-spacecraft phasing simulation to achieve a 15-degree
RAAN spacing using differential J2 drift.

Scoring (total 100 pts, pass >= 70):
  - script_created (10): Script modified/created during task window
  - simulation_structure (20): >= 2 spacecraft and >= 2 impulsive burns found in script
  - report_created (10): Results file generated
  - delta_v_accurate (20): Total DeltaV in expected range [265, 290] m/s
  - duration_accurate (25): Drift duration in expected range [105, 120] days
  - raan_target_met (15): Final RAAN difference in expected range [14.5, 15.5] degrees

Pass condition: score >= 70 AND duration_accurate AND delta_v_accurate
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_constellation_plane_phasing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    dv_min = metadata.get('expected_deltav_min_ms', 265.0)
    dv_max = metadata.get('expected_deltav_max_ms', 290.0)
    dur_min = metadata.get('expected_duration_min_days', 105.0)
    dur_max = metadata.get('expected_duration_max_days', 120.0)
    raan_min = metadata.get('expected_raan_diff_min_deg', 14.5)
    raan_max = metadata.get('expected_raan_diff_max_deg', 15.5)

    scores = {
        "script_created": 10,
        "simulation_structure": 20,
        "report_created": 10,
        "delta_v_accurate": 20,
        "duration_accurate": 25,
        "raan_target_met": 15,
    }

    total_score = 0
    feedback = []
    dv_ok = False
    dur_ok = False

    # Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Check script created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script was successfully created/modified during task.")
    elif isinstance(script_file, dict) and script_file.get('exists'):
        # Allow partial credit if it exists but timestamps are messy
        total_score += scores["script_created"] // 2
        feedback.append("Script found, but timestamps indicate it wasn't strictly created during the task.")
    else:
        feedback.append("Script not created.")

    # 2. Check simulation structure (multi-spacecraft, multi-burn)
    sc_count = task_result.get('spacecraft_count', 0)
    burn_count = task_result.get('burn_count', 0)
    if sc_count >= 2 and burn_count >= 2:
        total_score += scores["simulation_structure"]
        feedback.append(f"Simulation structure valid: {sc_count} spacecraft, {burn_count} burns.")
    else:
        feedback.append(f"Simulation structure invalid: found {sc_count} spacecraft, {burn_count} burns (expected >= 2 of each).")

    # 3. Check report created
    report_file = task_result.get('results_file', {})
    if isinstance(report_file, dict) and report_file.get('exists'):
        total_score += scores["report_created"]
        feedback.append("Results report generated.")
    else:
        feedback.append("Results report (phasing_results.txt) not found.")

    # Safely parse numeric results
    try:
        dv_val = float(task_result.get('total_deltav_ms', 0.0))
    except (ValueError, TypeError):
        dv_val = 0.0

    try:
        dur_val = float(task_result.get('drift_duration_days', 0.0))
    except (ValueError, TypeError):
        dur_val = 0.0

    try:
        raan_val = float(task_result.get('final_raan_diff_deg', 0.0))
    except (ValueError, TypeError):
        raan_val = 0.0

    # 4. Verify DeltaV accuracy
    if dv_min <= dv_val <= dv_max:
        total_score += scores["delta_v_accurate"]
        dv_ok = True
        feedback.append(f"Total DeltaV accurate: {dv_val:.2f} m/s (expected {dv_min}-{dv_max}).")
    else:
        feedback.append(f"Total DeltaV inaccurate: {dv_val:.2f} m/s (expected {dv_min}-{dv_max}).")

    # 5. Verify Drift Duration accuracy
    if dur_min <= dur_val <= dur_max:
        total_score += scores["duration_accurate"]
        dur_ok = True
        feedback.append(f"Drift Duration accurate: {dur_val:.2f} days (expected {dur_min}-{dur_max}).")
    else:
        feedback.append(f"Drift Duration inaccurate: {dur_val:.2f} days (expected {dur_min}-{dur_max}).")

    # 6. Verify Final RAAN Diff
    if raan_min <= raan_val <= raan_max:
        total_score += scores["raan_target_met"]
        feedback.append(f"Final RAAN difference target met: {raan_val:.2f} deg.")
    else:
        feedback.append(f"Final RAAN difference missed target: {raan_val:.2f} deg (expected ~15.0).")

    # Final pass conditions
    passed = (total_score >= 70) and dv_ok and dur_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "deltav": dv_val,
            "duration": dur_val,
            "raan_diff": raan_val,
            "spacecraft_count": sc_count,
            "burn_count": burn_count
        }
    }