#!/usr/bin/env python3
"""
Verifier for middle_floor_equip_load_reduction task.

Criteria:
1. Simulation ran during session (15 pts)
2. Project saved (5 pts)
3. M.* Spaces updated to 0.65 W/sqft (14 pts * 5 spaces = 70 pts)
4. Non-M.* Spaces NOT updated (10 pts)

Pass Threshold: 60 pts AND Simulation Ran AND >= 3 M.* spaces correct.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\task_result.json"

def verify_middle_floor_equip_load_reduction(traj, env_info, task_info):
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
    
    # 1. Verify Simulation Run (15 pts)
    sim_new = result.get('sim_file_is_new', False)
    if sim_new:
        score += 15
        feedback.append("Simulation ran successfully (+15).")
    else:
        feedback.append("Simulation NOT run or outputs are stale.")

    # 2. Verify Project Saved (5 pts)
    inp_saved = result.get('inp_file_saved', False)
    if inp_saved:
        score += 5
        feedback.append("Project saved (+5).")
    else:
        feedback.append("Project NOT saved.")

    # 3. Verify Space Values
    space_values = result.get('space_equip_values', {})
    target_val = 0.65
    tolerance = 0.02
    
    m_spaces_correct = 0
    m_spaces_total = 0
    non_m_spaces_changed = 0
    
    # Identify M.* spaces
    for name, val_str in space_values.items():
        try:
            val = float(val_str)
        except ValueError:
            continue

        if name.startswith("M.") or name.startswith("M "): # Handle "M." or "M " prefix
            m_spaces_total += 1
            if abs(val - target_val) <= tolerance:
                m_spaces_correct += 1
                feedback.append(f"Space '{name}' correct: {val} (+14).")
            else:
                feedback.append(f"Space '{name}' incorrect: {val} (expected {target_val}).")
        else:
            # Check for unintended changes
            # We assume non-M spaces should be approx 0.75-1.0 (baseline). 
            # If they are exactly 0.65, user likely did a global replace.
            if abs(val - target_val) <= tolerance:
                non_m_spaces_changed += 1

    # Score M.* spaces (max 70 pts)
    # We expect 5 M.* spaces usually. 14 pts each.
    score += (m_spaces_correct * 14)

    # 4. Penalty/Bonus for collateral damage (10 pts)
    if non_m_spaces_changed == 0:
        score += 10
        feedback.append("No unintended changes to other floors (+10).")
    else:
        feedback.append(f"WARNING: {non_m_spaces_changed} non-target spaces were modified to 0.65.")

    # Cap score
    score = min(score, 100)

    # Pass determination
    # Must have run sim AND got at least 3/5 spaces correct
    passed = (score >= 60) and sim_new and (m_spaces_correct >= 3)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }