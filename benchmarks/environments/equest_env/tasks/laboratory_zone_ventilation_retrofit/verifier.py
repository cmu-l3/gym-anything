#!/usr/bin/env python3
"""
Verifier for laboratory_zone_ventilation_retrofit task.

The agent must:
1. Locate the Ground Floor East zone ("G.East Perim Zn").
2. Set THROTTLING-RANGE = 0.5.
3. Set OA-FLOW/AREA = 1.0.
4. Run simulation (SIM file updated).
5. Save project.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Path inside the container (Windows path mapped)
RESULT_PATH = "C:\\Users\\Docker\\laboratory_zone_ventilation_retrofit_result.json"

def verify_laboratory_retrofit(traj, env_info, task_info):
    """
    Verifies the eQUEST model update for lab retrofit.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    sim_ran = result.get('sim_ran_during_session', False)
    zone_found = result.get('zone_found', False)
    throttling_range = result.get('throttling_range', -1)
    oa_flow = result.get('oa_flow_area', -1)
    global_count = result.get('global_modification_count', 0)

    # Criterion 1: Simulation Run (20 pts)
    if sim_ran:
        score += 20
        feedback_parts.append("Simulation run confirmed (+20)")
    else:
        feedback_parts.append("Simulation NOT run during session")

    # Criterion 2: Target Zone Found (20 pts)
    if zone_found:
        score += 20
        feedback_parts.append(f"Target zone identified: {result.get('target_zone_name')} (+20)")
    else:
        feedback_parts.append("Target zone (G.East) not found or not modified")

    # Criterion 3: Throttling Range (30 pts)
    # Target: 0.5
    if abs(throttling_range - 0.5) < 0.05:
        score += 30
        feedback_parts.append("Throttling range correctly set to 0.5 (+30)")
    elif throttling_range != -1:
        feedback_parts.append(f"Throttling range incorrect: {throttling_range} (Expected 0.5)")
    else:
        feedback_parts.append("Throttling range not found")

    # Criterion 4: OA Flow (30 pts)
    # Target: 1.0
    if abs(oa_flow - 1.0) < 0.05:
        score += 30
        feedback_parts.append("OA Flow/Area correctly set to 1.0 (+30)")
    elif oa_flow != -1:
        feedback_parts.append(f"OA Flow incorrect: {oa_flow} (Expected 1.0)")
    else:
        feedback_parts.append("OA Flow not found")

    # Anti-Gaming: Global Changes
    # If the user changed ALL zones to 0.5 throttling range, that's lazy/wrong.
    # The starting model usually has >5 zones.
    # If global_count > 10 (arbitrary threshold for "too many"), penalize.
    if global_count > 10:
        score -= 20
        feedback_parts.append(f"PENALTY: Throttling range changed on {global_count} zones. Task specified Ground Floor East ONLY (-20)")

    final_passed = score >= 70 and sim_ran

    return {
        "passed": final_passed,
        "score": max(0, score), # No negative scores
        "feedback": " | ".join(feedback_parts)
    }