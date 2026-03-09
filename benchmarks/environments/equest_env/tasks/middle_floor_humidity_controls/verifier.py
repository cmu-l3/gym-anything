#!/usr/bin/env python3
"""
Verifier for middle_floor_humidity_controls task.

The agent must:
1. Update 5 Middle Floor systems (M.*) in eQUEST.
2. Set MIN-HUMIDITY = 30
3. Set MAX-HUMIDITY = 60
4. Set HUMIDIFIER-TYPE = ELECTRIC
5. Run Simulation.

Scoring (100 pts):
- Simulation ran: 10 pts
- MIN-HUMIDITY correct: 30 pts (6 per system)
- MAX-HUMIDITY correct: 30 pts (6 per system)
- HUMIDIFIER-TYPE correct: 30 pts (6 per system)

Pass: Score >= 60 AND Simulation Ran AND MIN-HUMIDITY correct on >= 3 systems.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILENAME = "middle_floor_humidity_controls_result.json"
RESULT_PATH_WIN = f"C:\\Users\\Docker\\{RESULT_FILENAME}"

def verify_middle_floor_humidity_controls(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env(RESULT_PATH_WIN, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve task results. Ensure export_result script ran successfully."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Logic
    score = 0
    feedback = []
    
    # 1. Simulation Check (10 pts)
    sim_ran = result.get("sim_file_is_new", False)
    if sim_ran:
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation did not run or file not saved.")

    # 2. Check System Parameters
    summary = result.get("score_summary", {})
    
    # Min Humidity (30 pts max, 6 per system)
    min_h_count = summary.get("min_humidity_correct", 0)
    score += (min_h_count * 6)
    feedback.append(f"MIN-HUMIDITY correct on {min_h_count}/5 systems (+{min_h_count*6}).")

    # Max Humidity (30 pts max, 6 per system)
    max_h_count = summary.get("max_humidity_correct", 0)
    score += (max_h_count * 6)
    feedback.append(f"MAX-HUMIDITY correct on {max_h_count}/5 systems (+{max_h_count*6}).")

    # Humidifier Type (30 pts max, 6 per system)
    hum_type_count = summary.get("humidifier_type_correct", 0)
    score += (hum_type_count * 6)
    feedback.append(f"HUMIDIFIER-TYPE correct on {hum_type_count}/5 systems (+{hum_type_count*6}).")

    # Pass Criteria
    # Need 60 points total, simulation must have run, and at least 3 systems must have MIN-HUMIDITY correct (proxy for effort)
    passed = (score >= 60) and sim_ran and (min_h_count >= 3)

    if not passed:
        if not sim_ran:
            feedback.append("FAIL: Simulation must be run to pass.")
        if min_h_count < 3:
            feedback.append("FAIL: Fewer than 3 systems had correct MIN-HUMIDITY.")
        if score < 60:
            feedback.append(f"FAIL: Score {score} below threshold of 60.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }