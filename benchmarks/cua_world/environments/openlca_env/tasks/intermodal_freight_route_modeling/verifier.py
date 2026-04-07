#!/usr/bin/env python3
"""
Verifier for Intermodal Freight Route Modeling task.

SCORING CRITERIA:
1. Process Creation (20 pts): 'freight_route_chicago_wi' exists in DB.
2. Rail Input Logic (25 pts): Input amount matches 20t * 400km (~8000 tkm).
3. Truck Input Logic (25 pts): Input amount matches 20t * 80km (~1600 tkm).
4. Result Export (15 pts): CSV file exists with GWP content.
5. Anti-gaming (15 pts): File created during task, app running.

VLM Verification (Trajectory):
- Confirm usage of standard USLCI processes (Train/Truck).
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_intermodal_freight_route(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []
    
    # Targets from metadata or task description
    TARGET_RAIL = 8000.0
    TARGET_TRUCK = 1600.0
    TOLERANCE = 0.05  # 5% tolerance

    # 1. Process Creation (20 pts)
    if result.get("process_found", False):
        score += 20
        feedback.append("Process 'freight_route_chicago_wi' created.")
    else:
        feedback.append("Process 'freight_route_chicago_wi' NOT found in database.")

    # 2 & 3. Input Logic (50 pts total)
    amounts = result.get("exchange_amounts", [])
    rail_found = False
    truck_found = False
    
    # We check if the calculated amounts exist in the process exchanges
    # This is robust because 8000 and 1600 are specific enough to be unlikely by chance
    for amt in amounts:
        try:
            val = float(amt)
            # Check Rail (8000)
            if abs(val - TARGET_RAIL) / TARGET_RAIL <= TOLERANCE:
                rail_found = True
            # Check Truck (1600)
            if abs(val - TARGET_TRUCK) / TARGET_TRUCK <= TOLERANCE:
                truck_found = True
        except (ValueError, TypeError):
            continue

    if rail_found:
        score += 25
        feedback.append("Rail transport amount correct (~8000 tkm).")
    else:
        feedback.append(f"Rail transport amount (~8000 tkm) NOT found. Found: {amounts}")

    if truck_found:
        score += 25
        feedback.append("Truck transport amount correct (~1600 tkm).")
    else:
        feedback.append("Truck transport amount (~1600 tkm) NOT found.")

    # 4. Result Export (15 pts)
    if result.get("file_exists") and result.get("has_gwp_content"):
        score += 15
        feedback.append("GWP result exported successfully.")
    elif result.get("file_exists"):
        score += 5
        feedback.append("Result file exists but content unclear.")
    else:
        feedback.append("Result file not found.")

    # 5. Anti-gaming / App Usage (15 pts - scaled)
    # If app is running and file was created during task
    if result.get("openlca_running"):
        score += 5
    if result.get("file_created_during_task"):
        score += 10
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }