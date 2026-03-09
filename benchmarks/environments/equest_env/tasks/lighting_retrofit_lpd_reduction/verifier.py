#!/usr/bin/env python3
"""
Verifier for lighting_retrofit_lpd_reduction task.

The agent must:
1. Update LIGHTING-W/AREA to 0.65 for all Ground Floor (G.*) spaces.
2. Update LIGHTING-W/AREA to 0.65 for all Top Floor (T.*) spaces.
3. Run the simulation (producing a new .SIM file).

Target Spaces:
- Ground: G.S11, G.E12, G.N13, G.W14, G.C15
- Top:    T.S31, T.E32, T.N33, T.W34, T.C35

Scoring:
- Simulation Run: 10 pts
- Each Correct Space (10 spaces): 9 pts each (Total 90)
- Pass Threshold: 60 pts + Simulation Run
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\lighting_retrofit_result.json"
TARGET_LPD = 0.65
TOLERANCE = 0.01

TARGET_SPACES = [
    "G.S11", "G.E12", "G.N13", "G.W14", "G.C15",
    "T.S31", "T.E32", "T.N33", "T.W34", "T.C35"
]

def verify_lighting_retrofit_lpd_reduction(traj, env_info, task_info):
    """
    Verifies that the LPD was reduced and simulation was run.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Load Result JSON
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
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
    
    # 2. Verify Simulation Run (10 pts)
    # Anti-gaming: .SIM file must be new (modified after task start)
    sim_run = result.get("sim_file_is_new", False)
    if sim_run:
        score += 10
        feedback_parts.append("Simulation ran successfully (+10)")
    else:
        feedback_parts.append("Simulation NOT run (or run before task started)")

    # 3. Verify Space LPDs (90 pts total, 9 per space)
    spaces_data = result.get("spaces", {})
    correct_count = 0
    
    for space_name in TARGET_SPACES:
        # Check if space exists in extracted data
        if space_name not in spaces_data:
            feedback_parts.append(f"Space {space_name} not found or LPD not set")
            continue
            
        try:
            val = float(spaces_data[space_name])
            if abs(val - TARGET_LPD) <= TOLERANCE:
                score += 9
                correct_count += 1
            else:
                feedback_parts.append(f"{space_name}: {val} (Expected {TARGET_LPD})")
        except (ValueError, TypeError):
             feedback_parts.append(f"{space_name}: Invalid value")

    # 4. Generate Feedback and Final Status
    if correct_count == len(TARGET_SPACES):
        feedback_parts.append(f"All {correct_count} spaces updated correctly (+90)")
    else:
        feedback_parts.append(f"{correct_count}/{len(TARGET_SPACES)} spaces correct")

    # Pass Condition: Score >= 60 AND Simulation must have run
    passed = (score >= 60) and sim_run
    
    final_feedback = " | ".join(feedback_parts)
    if not sim_run:
        final_feedback += " | FAIL: Simulation run required to pass."

    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }