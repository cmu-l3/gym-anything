#!/usr/bin/env python3
"""
Verifier for leo_drag_makeup_maneuvers@1

Agent must simulate 30 days of LEO orbit maintenance, triggering prograde burns
when SMA drops below a threshold, and extract key maintenance metrics.

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created during task window.
  - logic_correct (15): Loop/If logic and ImpulsiveBurn defined in script.
  - log_written (10): Maneuver log file created.
  - summary_written (10): Summary report written with required fields.
  - physics_burns_valid (15): Total burns in physically expected range [2, 8].
  - physics_dv_valid (15): Total DeltaV in physically expected range [1.0, 8.0] m/s.
  - physics_interval_valid (10): Avg interval between burns is reasonable [3.0, 20.0] days.
  - final_sma_valid (15): Final SMA is near the restored target 6871.14 km (within tolerance).

Pass condition: score >= 60 AND logic_correct AND physics_burns_valid AND physics_dv_valid
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_leo_drag_makeup_maneuvers(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    burns_min = metadata.get('burns_min', 2)
    burns_max = metadata.get('burns_max', 8)
    dv_min = metadata.get('total_dv_min_mps', 1.0)
    dv_max = metadata.get('total_dv_max_mps', 8.0)
    int_min = metadata.get('interval_min_days', 3.0)
    int_max = metadata.get('interval_max_days', 20.0)
    sma_min = metadata.get('final_sma_min_km', 6868.0)
    sma_max = metadata.get('final_sma_max_km', 6874.0)

    scores = {
        "script_created": 10,
        "logic_correct": 15,
        "log_written": 10,
        "summary_written": 10,
        "physics_burns_valid": 15,
        "physics_dv_valid": 15,
        "physics_interval_valid": 10,
        "final_sma_valid": 15,
    }

    total_score = 0
    feedback = []
    
    # Critical pass conditions
    logic_ok = False
    burns_ok = False
    dv_ok = False

    # Load task result
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

    # 1. Script created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created or modified during task window.")

    # 2. Logic correctness
    has_loop = task_result.get('has_loop_logic', False)
    has_burn = task_result.get('has_burn_definition', False)
    if has_loop and has_burn:
        total_score += scores["logic_correct"]
        logic_ok = True
        feedback.append("Loop logic and ImpulsiveBurn identified in script.")
    else:
        if not has_loop:
            feedback.append("No While/If branching logic found in script (required for event-based maintenance).")
        if not has_burn:
            feedback.append("No ImpulsiveBurn definition found in script.")

    # 3. Log and Summary written
    log_file = task_result.get('log_file', {})
    summary_file = task_result.get('summary_file', {})
    
    if isinstance(log_file, dict) and log_file.get('exists'):
        total_score += scores["log_written"]
        feedback.append("Maneuver log file written.")
    else:
        feedback.append("Maneuver log file missing.")
        
    if isinstance(summary_file, dict) and summary_file.get('exists'):
        total_score += scores["summary_written"]
        feedback.append("Maintenance summary report written.")
    else:
        feedback.append("Maintenance summary report missing.")

    # 4. Physics Validation
    try:
        total_burns = float(task_result.get('total_burns', 0))
    except ValueError:
        total_burns = 0.0

    try:
        total_dv = float(task_result.get('total_deltav_ms', 0))
    except ValueError:
        total_dv = 0.0

    try:
        avg_int = float(task_result.get('avg_interval_days', 0))
    except ValueError:
        avg_int = 0.0

    try:
        final_sma = float(task_result.get('final_sma_km', 0))
    except ValueError:
        final_sma = 0.0

    # Evaluate Physical bounds
    if burns_min <= total_burns <= burns_max:
        total_score += scores["physics_burns_valid"]
        burns_ok = True
        feedback.append(f"Total burns valid: {total_burns} (expected {burns_min}-{burns_max}).")
    else:
        feedback.append(f"Total burns out of expected range: {total_burns}.")

    if dv_min <= total_dv <= dv_max:
        total_score += scores["physics_dv_valid"]
        dv_ok = True
        feedback.append(f"Total DeltaV valid: {total_dv:.2f} m/s (expected {dv_min}-{dv_max} m/s).")
    else:
        feedback.append(f"Total DeltaV out of expected range: {total_dv:.2f} m/s.")

    if int_min <= avg_int <= int_max:
        total_score += scores["physics_interval_valid"]
        feedback.append(f"Avg maneuver interval valid: {avg_int:.1f} days.")
    else:
        feedback.append(f"Avg maneuver interval out of expected range: {avg_int:.1f} days.")

    if sma_min <= final_sma <= sma_max:
        total_score += scores["final_sma_valid"]
        feedback.append(f"Final SMA valid: {final_sma:.2f} km.")
    else:
        feedback.append(f"Final SMA out of tolerance: {final_sma:.2f} km (expected near 6871.14 km).")

    # Final scoring
    critical_pass = logic_ok and burns_ok and dv_ok
    passed = (total_score >= 60) and critical_pass

    if not critical_pass:
        feedback.append("CRITICAL FAILURE: Required physics logic or physically valid metrics were not met.")

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "total_burns": total_burns,
            "total_dv_ms": total_dv,
            "avg_interval_days": avg_int,
            "final_sma_km": final_sma
        }
    }