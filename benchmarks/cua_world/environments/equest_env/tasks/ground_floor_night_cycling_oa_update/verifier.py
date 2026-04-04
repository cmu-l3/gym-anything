#!/usr/bin/env python3
"""
Verifier for ground_floor_night_cycling_oa_update task.

Checks:
1. Simulation was run (Sim file exists and is new).
2. For 5 Ground Floor Systems (G.S01, G.E02, G.N03, G.W04, G.C05):
   - NIGHT-CYCLE-CTRL should be 'CYCLE-ON-ANY'
   - MIN-OUTSIDE-AIR should be 200

Scoring:
- Simulation Run: 10 pts
- Night Cycle Correct: 9 pts * 5 systems = 45 pts
- Min OA Correct: 9 pts * 5 systems = 45 pts
Total: 100 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Windows path inside container where result is saved
RESULT_PATH = "C:\\Users\\Docker\\ground_floor_night_cycling_oa_update_result.json"
TARGET_SYSTEMS = ["G.S01", "G.E02", "G.N03", "G.W04", "G.C05"]
EXPECTED_NIGHT_CYCLE = "CYCLE-ON-ANY"
EXPECTED_MIN_OA = 200.0
OA_TOLERANCE = 5.0  # Allow slight float variations

def verify_ground_floor_night_cycling_oa_update(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve task results. Did you run the export script?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Score Simulation (10 pts)
    sim_is_new = result.get("sim_file_is_new", False)
    if sim_is_new:
        score += 10
        feedback_parts.append("Simulation run successfully (+10)")
    else:
        feedback_parts.append("Simulation NOT run during task (0/10)")

    # 3. Score System Parameters
    systems_data = result.get("systems", {})
    
    night_cycle_correct_count = 0
    oa_correct_count = 0
    
    for sys_name in TARGET_SYSTEMS:
        sys_data = systems_data.get(sys_name, {})
        
        # Check Night Cycle
        actual_nc = sys_data.get("NightCycle", "MISSING")
        if actual_nc == EXPECTED_NIGHT_CYCLE:
            score += 9
            night_cycle_correct_count += 1
        
        # Check Min OA
        actual_oa_raw = sys_data.get("MinOA", -1)
        try:
            actual_oa = float(actual_oa_raw)
            if abs(actual_oa - EXPECTED_MIN_OA) <= OA_TOLERANCE:
                score += 9
                oa_correct_count += 1
        except (ValueError, TypeError):
            pass

    # 4. Construct Feedback
    feedback_parts.append(f"Night Cycle Correct: {night_cycle_correct_count}/5 systems")
    feedback_parts.append(f"Min OA Correct: {oa_correct_count}/5 systems")
    
    if night_cycle_correct_count < 5:
        feedback_parts.append(f"Expected Night Cycle: {EXPECTED_NIGHT_CYCLE}")
    if oa_correct_count < 5:
        feedback_parts.append(f"Expected Min OA: {EXPECTED_MIN_OA}")

    # 5. Determine Pass/Fail
    # Pass threshold: 60 points AND simulation must be run
    passed = (score >= 60) and sim_is_new

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }