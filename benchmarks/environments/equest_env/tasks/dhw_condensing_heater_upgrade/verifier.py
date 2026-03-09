#!/usr/bin/env python3
"""
Verifier for dhw_condensing_heater_upgrade task.

The agent must:
1. Update HEAT-INPUT-RATIO to ~1.05263 (95% eff)
2. Update TANK-UA to 3.0
3. Update AQUASTAT-SETPT-T to 125
4. Run Simulation (generate new .SIM file)

Scoring (100 pts total):
- Simulation ran during session: 15 pts
- HEAT-INPUT-RATIO correct: 30 pts (split per heater)
- TANK-UA correct: 25 pts (split per heater)
- AQUASTAT-SETPT-T correct: 30 pts (split per heater)

Pass Threshold: 60 pts AND simulation ran.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected Values
TARGET_HIR = 1.05263
TARGET_UA = 3.0
TARGET_SETPT = 125.0
TOLERANCE_HIR = 0.005
TOLERANCE_UA = 0.2
TOLERANCE_SETPT = 1.0

RESULT_FILENAME = "dhw_upgrade_result.json"

def verify_dhw_condensing_heater_upgrade(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(f"C:/Users/Docker/{RESULT_FILENAME}", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to read task result file. Ensure the project was saved and simulation run."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Simulation Run (15 pts)
    sim_run = result.get("sim_file_is_new", False)
    if sim_run:
        score += 15
        feedback_parts.append("Simulation ran successfully (+15).")
    else:
        feedback_parts.append("Simulation NOT run or outputs not new.")

    # 2. Verify Heater Parameters
    heaters = result.get("heaters_data", [])
    num_heaters = len(heaters)
    
    if num_heaters == 0:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "No DW-HEATER components found in the project file. " + " | ".join(feedback_parts)
        }

    # Points per parameter type (distributed across all heaters)
    pts_hir = 30.0
    pts_ua = 25.0
    pts_setpt = 30.0

    hir_correct_count = 0
    ua_correct_count = 0
    setpt_correct_count = 0

    for heater in heaters:
        # Check HIR
        try:
            val = float(heater.get("heat_input_ratio", -1))
            if abs(val - TARGET_HIR) <= TOLERANCE_HIR:
                hir_correct_count += 1
        except (TypeError, ValueError):
            pass

        # Check UA
        try:
            val = float(heater.get("tank_ua", -1))
            if abs(val - TARGET_UA) <= TOLERANCE_UA:
                ua_correct_count += 1
        except (TypeError, ValueError):
            pass

        # Check Setpoint
        try:
            val = float(heater.get("aquastat_setpt_t", -1))
            if abs(val - TARGET_SETPT) <= TOLERANCE_SETPT:
                setpt_correct_count += 1
        except (TypeError, ValueError):
            pass

    # Calculate scores
    score_hir = (hir_correct_count / num_heaters) * pts_hir
    score_ua = (ua_correct_count / num_heaters) * pts_ua
    score_setpt = (setpt_correct_count / num_heaters) * pts_setpt

    score += score_hir + score_ua + score_setpt
    
    # Generate detailed feedback
    if hir_correct_count == num_heaters:
        feedback_parts.append(f"All heaters have correct HEAT-INPUT-RATIO (+{pts_hir}).")
    else:
        feedback_parts.append(f"{hir_correct_count}/{num_heaters} heaters have correct HEAT-INPUT-RATIO.")

    if ua_correct_count == num_heaters:
        feedback_parts.append(f"All heaters have correct TANK-UA (+{pts_ua}).")
    else:
        feedback_parts.append(f"{ua_correct_count}/{num_heaters} heaters have correct TANK-UA.")

    if setpt_correct_count == num_heaters:
        feedback_parts.append(f"All heaters have correct AQUASTAT-SETPT-T (+{pts_setpt}).")
    else:
        feedback_parts.append(f"{setpt_correct_count}/{num_heaters} heaters have correct AQUASTAT-SETPT-T.")

    # Final Result
    final_score = min(round(score), 100)
    passed = final_score >= 60 and sim_run

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }