#!/usr/bin/env python3
"""
Verifier for create_fitts_law_task.

Verification Strategy:
1. Programmatic: Check filesystem for .psyexp and .csv
2. Programmatic: Verify CSV math ($pos_x = Amp/2 * Dir$)
3. Programmatic: Parse XML to verify Experiment Structure (Routines, Mouse interactions, Variable usage)
4. VLM: Visual confirmation of Builder state or output if needed (secondary)
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_fitts_law_task(traj, env_info, task_info):
    """Verify Fitts Law task creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from export_result.sh
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. File Existence (10 pts)
    if result.get("files_exist", False):
        score += 10
        feedback.append("Files created successfully.")
    else:
        feedback.append("Required files (.psyexp or .csv) not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. CSV Content (30 pts)
    if result.get("csv_structure_valid", False):
        score += 5
        feedback.append("CSV headers correct.")
        
        math_score = result.get("csv_math_score", 0)
        # We expect 12 rows. 
        # Score proportional to correctness
        points_math = (math_score / 100) * 25
        score += points_math
        feedback.append(f"CSV Math Accuracy: {math_score:.1f}% (+{points_math:.1f} pts).")
        
        total_rows = result.get("total_rows", 0)
        if total_rows == 12:
             feedback.append("Row count correct (12).")
        else:
             feedback.append(f"Row count incorrect ({total_rows}/12).")
    else:
        feedback.append("CSV missing required columns.")

    # 3. Experiment Structure (Home Routine) (20 pts)
    comps = result.get("components_valid", {})
    if "home" in str(result.get("routines_found", [])).lower():
        score += 5
        feedback.append("Home routine found.")
        if comps.get("home_mouse", False):
            score += 15
            feedback.append("Home mouse interaction valid (clickable limited).")
        else:
            feedback.append("Home mouse component missing or not configured to click specific object.")
    else:
        feedback.append("Home routine missing.")

    # 4. Experiment Structure (Reach Routine + Variables) (20 pts)
    if "reach" in str(result.get("routines_found", [])).lower():
        score += 5
        feedback.append("Reach routine found.")
        
        vars_used = result.get("variable_usage", {})
        if vars_used.get("pos_x", False) and vars_used.get("target_w", False):
            score += 10
            feedback.append("Stimulus uses CSV variables for pos/size.")
        else:
            feedback.append("Stimulus does not use expected variables ($pos_x, $target_w).")
            
        if comps.get("reach_mouse", False):
            score += 5
            feedback.append("Reach mouse interaction valid.")
    else:
        feedback.append("Reach routine missing.")

    # 5. Interaction Logic / Loop (20 pts)
    if comps.get("loop_linked", False):
        score += 10
        feedback.append("Loop linked to conditions file.")
    
    if result.get("units_correct", False):
        score += 10
        feedback.append("Experiment units set to 'height'.")
    else:
        feedback.append("Experiment units NOT set to 'height' (critical for layout).")

    # Final Pass check
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }