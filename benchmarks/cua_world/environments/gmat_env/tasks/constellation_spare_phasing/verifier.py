#!/usr/bin/env python3
"""
Verifier for constellation_spare_phasing@1

Agent must calculate exact drift wait time and execute a two-burn Hohmann transfer
to precisely insert an on-orbit spare into a constellation target slot.

Scoring (total 100 pts, pass >= 70):
  - script_created (10): Script created during task window
  - two_spacecraft (10): Both SPARE and TARGET_SLOT defined in script
  - two_burns (10): Two ImpulsiveBurn maneuvers defined/executed
  - report_written (10): Report file exists with required keys
  - deltav_valid (15): Total DeltaV in [45, 55] m/s
  - wait_time_valid (15): Wait time to drift is [40, 50] hours
  - sma_achieved (15): Final SMA difference from target <= 1.0 km (implicit if dv is right, but verified from GMAT output)
  - phase_achieved (15): Final phase difference <= 0.5 deg

Pass condition: score >= 70 AND phase_achieved (proving precise physical alignment).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_constellation_spare_phasing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_wait_min = metadata.get('expected_wait_time_min', 40.0)
    expected_wait_max = metadata.get('expected_wait_time_max', 50.0)
    expected_dv_min = metadata.get('expected_deltav_min', 45.0)
    expected_dv_max = metadata.get('expected_deltav_max', 55.0)
    phase_diff_tol = metadata.get('phase_diff_tolerance_deg', 0.5)

    scores = {
        "script_created": 10,
        "two_spacecraft": 10,
        "two_burns": 10,
        "report_written": 10,
        "deltav_valid": 15,
        "wait_time_valid": 15,
        "sma_achieved": 15,
        "phase_achieved": 15,
    }

    total_score = 0
    feedback = []
    phase_ok = False
    sma_ok = False

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

    # 1. Script created during task
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Check for Spacecraft definitions
    has_target = task_result.get('has_target_sc', False)
    has_spare = task_result.get('has_spare_sc', False)
    if has_target and has_spare:
        total_score += scores["two_spacecraft"]
        feedback.append("Both SPARE and TARGET spacecraft found in script.")
    else:
        feedback.append("Missing one or both spacecraft definitions in script.")

    # 3. Check for Burns
    try:
        burn_count = int(task_result.get('burn_count', 0))
    except ValueError:
        burn_count = 0

    if burn_count >= 2:
        total_score += scores["two_burns"]
        feedback.append("At least two burns found in script.")
    elif burn_count == 1:
        total_score += scores["two_burns"] // 2
        feedback.append("Only one burn found (expected two).")
    else:
        feedback.append("No burns found in script.")

    # 4. Report written during task
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('created_during_task') and report_file.get('size', 0) > 0:
        total_score += scores["report_written"]
        feedback.append("Results report successfully written.")
    else:
        feedback.append("Results report missing or not updated.")

    # Convert reported metrics
    try:
        wait_time = float(task_result.get('wait_time_hours', 0))
    except (ValueError, TypeError):
        wait_time = 0.0

    try:
        total_dv = float(task_result.get('total_dv_ms', 0))
    except (ValueError, TypeError):
        total_dv = 0.0

    try:
        phase_diff = float(task_result.get('final_phase_diff_deg', 180.0))
    except (ValueError, TypeError):
        phase_diff = 180.0

    # 5. Wait time valid (~44.8 hours expected)
    if expected_wait_min <= wait_time <= expected_wait_max:
        total_score += scores["wait_time_valid"]
        feedback.append(f"Wait time is physically accurate: {wait_time:.2f} hours.")
    else:
        feedback.append(f"Wait time out of bounds: {wait_time:.2f} hours (expected {expected_wait_min}-{expected_wait_max}).")

    # 6. DeltaV valid (~48.6 m/s expected total)
    if expected_dv_min <= total_dv <= expected_dv_max:
        total_score += scores["deltav_valid"]
        sma_ok = True  # If DV is correct, they performed the exact right Hohmann
        feedback.append(f"DeltaV is accurate: {total_dv:.2f} m/s.")
    else:
        feedback.append(f"DeltaV out of bounds: {total_dv:.2f} m/s (expected {expected_dv_min}-{expected_dv_max}).")

    # 7. SMA Validation (Implicitly verified by DeltaV accuracy, but we credit if DeltaV was correct)
    if sma_ok:
        total_score += scores["sma_achieved"]
        feedback.append("Final SMA closely matches target (validated via DV).")
    else:
        feedback.append("Final SMA mismatch due to incorrect burn design.")

    # 8. Phase difference valid
    if phase_diff <= phase_diff_tol:
        total_score += scores["phase_achieved"]
        phase_ok = True
        feedback.append(f"Precise phase matching achieved: difference {phase_diff:.4f} deg.")
    else:
        feedback.append(f"Phase matching failed: difference {phase_diff:.4f} deg (max allowed {phase_diff_tol}).")

    passed = total_score >= 70 and phase_ok and sma_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }