#!/usr/bin/env python3
"""
Verifier for ground_floor_baseboard_heating task.

Criteria:
1. Simulation ran during session (10 pts)
2. 4 Perimeter Zones (G.S11, G.E12, G.N13, G.W14):
   - BASEBOARD-SOURCE = ELECTRIC (5 pts each)
   - BASEBOARD-RATING = 5000 (±250) (5 pts each)
   - BASEBOARD-CTRL = THERMOSTATIC (5 pts each)
   (Total 60 pts for perimeter zones)
3. Core Zone (G.C15):
   - Must NOT have baseboard heating (Source != ELECTRIC or Rating missing) (10 pts)
4. Project Saved (checked via parsing success) (20 pts base for having readable data)

Pass Threshold: 60 pts AND Sim Ran AND >= 3 Perimeter Zones Correct.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\ground_floor_baseboard_heating_result.json"

PERIMETER_ZONES = ["G.S11", "G.E12", "G.N13", "G.W14"]
CORE_ZONE = "G.C15"

def verify_ground_floor_baseboard_heating(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

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
    feedback = []
    
    # 1. Simulation Check (10 pts)
    if result.get("sim_ran", False):
        score += 10
        feedback.append("Simulation ran successfully (+10)")
    else:
        feedback.append("Simulation did not run")

    zones_data = result.get("zones", {})
    correct_perimeter_count = 0

    # 2. Perimeter Zones Check (60 pts max)
    for z in PERIMETER_ZONES:
        z_data = zones_data.get(z, {})
        z_score = 0
        z_feedback = []
        
        # Source (5 pts)
        if z_data.get("Source") == "ELECTRIC":
            z_score += 5
        else:
            z_feedback.append(f"Source: {z_data.get('Source')}")

        # Rating (5 pts)
        try:
            rating = float(z_data.get("Rating", 0))
            if 4750 <= rating <= 5250:
                z_score += 5
            else:
                z_feedback.append(f"Rating: {rating}")
        except:
            z_feedback.append("Rating: invalid")

        # Ctrl (5 pts)
        if z_data.get("Ctrl") == "THERMOSTATIC":
            z_score += 5
        else:
            z_feedback.append(f"Ctrl: {z_data.get('Ctrl')}")

        score += z_score
        
        if z_score == 15:
            correct_perimeter_count += 1
            feedback.append(f"{z}: Perfect (+15)")
        elif z_score > 0:
            feedback.append(f"{z}: Partial (+{z_score}) - Issues: {', '.join(z_feedback)}")
        else:
            feedback.append(f"{z}: Failed (No correct settings)")

    # 3. Core Zone Check (10 pts)
    # Should NOT have electric baseboard
    core_data = zones_data.get(CORE_ZONE, {})
    core_source = core_data.get("Source", "NONE")
    
    if core_source != "ELECTRIC":
        score += 10
        feedback.append(f"Core Zone ({CORE_ZONE}) correctly left alone (+10)")
    else:
        feedback.append(f"Core Zone ({CORE_ZONE}) incorrectly modified with ELECTRIC baseboard (-0)")

    # 4. Save/File Existence (20 pts implied by reaching this point with valid data)
    # If we parsed zones, the file existed and was saved with *something*.
    if zones_data:
        score += 20
        feedback.append("Project file parsed successfully (+20)")

    passed = (score >= 60) and result.get("sim_ran", False) and (correct_perimeter_count >= 3)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }