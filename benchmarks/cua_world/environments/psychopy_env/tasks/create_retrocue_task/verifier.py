#!/usr/bin/env python3
"""
Verifier for create_retrocue_task.

Scoring Criteria:
1. Conditions File (40 pts):
   - Exists & Valid Columns (15 pts)
   - Correct Row Logic (25 pts)
2. Experiment Structure (45 pts):
   - Valid XML & Loop (10 pts)
   - Required Routines Sequence (20 pts)
   - Variable Linking (15 pts)
3. Execution (15 pts):
   - Data file generated (proof of run)

Total: 100 points. Pass threshold: 70 points.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_retrocue_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Retrieve result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/retrocue_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Verify Nonce
    try:
        temp_nonce = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/home/ga/.task_nonce", temp_nonce.name)
        with open(temp_nonce.name, 'r') as f:
            expected_nonce = f.read().strip()
        os.unlink(temp_nonce.name)
        
        if result.get("result_nonce") != expected_nonce:
             return {"passed": False, "score": 0, "feedback": "Integrity check failed (nonce mismatch)."}
    except:
        pass # Nonce check soft fail if file missing

    score = 0
    feedback = []

    # 1. Conditions File Analysis
    if result.get("cond_exists"):
        if result.get("cond_columns_valid"):
            score += 15
            feedback.append("Conditions file has valid columns.")
        else:
            feedback.append("Conditions file missing required columns.")
            
        # Logic Check
        logic_score = result.get("cond_logic_score", 0)
        row_count = result.get("cond_row_count", 0)
        if row_count >= 6:
            # Full points if at least 5/6 rows are logically correct
            if logic_score >= 5:
                score += 25
                feedback.append(f"Trial logic is correct ({logic_score}/{row_count} rows).")
            elif logic_score >= 3:
                score += 10
                feedback.append(f"Trial logic partially correct ({logic_score}/{row_count} rows).")
            else:
                feedback.append(f"Trial logic incorrect ({logic_score}/{row_count} rows).")
        else:
            feedback.append(f"Not enough rows in conditions file ({row_count}/6).")
    else:
        feedback.append("Conditions file not found.")

    # 2. Experiment Structure Analysis
    if result.get("exp_exists") and result.get("psyexp_valid_xml"):
        if result.get("has_loop"):
            score += 10
            feedback.append("Experiment loop configured.")
        else:
            feedback.append("No loop found in experiment.")

        routines = result.get("routines_found", [])
        required = ["encoding", "delay1", "cue", "delay2", "probe"]
        # Allow partial matching/case-insensitive
        routines_lower = [r.lower() for r in routines]
        found_req = [r for r in required if any(r in x for x in routines_lower)]
        
        if len(found_req) == 5:
            score += 20
            feedback.append("All required routines present.")
        elif len(found_req) >= 3:
            score += 10
            feedback.append(f"Missing some routines. Found: {found_req}")
        else:
            feedback.append("Experiment structure significantly incomplete.")

        if result.get("components_linked"):
            score += 15
            feedback.append("Stimulus components correctly linked to variables.")
        else:
            feedback.append("Components do not appear to use condition variables (e.g. $left_color).")
    else:
        feedback.append("Experiment file not found or invalid.")

    # 3. Execution Check
    if result.get("data_exists"):
        score += 15
        feedback.append("Experiment data generated.")
    else:
        feedback.append("No data file generated (did you run the experiment?).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }