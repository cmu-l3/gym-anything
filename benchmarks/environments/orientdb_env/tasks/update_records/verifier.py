#!/usr/bin/env python3
"""
Verifier for update_records task.

Checks:
1. Hotel Artemide Stars = 5
2. The Savoy Phone = +44-20-7836-5555
3. Copacabana Palace Type = Palace
4. Luca Rossi Surname = De Rossi
5. Anti-gaming: Values must have changed from initial state.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_records(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results and initial state
    results = {}
    initial_state = {}
    
    # Files to copy
    files = {
        'result': '/tmp/task_result.json',
        'initial': '/tmp/initial_state.json'
    }
    
    temp_files = []
    
    try:
        # Copy result
        t_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_files.append(t_res.name)
        copy_from_env(files['result'], t_res.name)
        with open(t_res.name, 'r') as f:
            results = json.load(f)
            
        # Copy initial state
        t_init = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_files.append(t_init.name)
        try:
            copy_from_env(files['initial'], t_init.name)
            with open(t_init.name, 'r') as f:
                initial_state = json.load(f)
        except Exception:
            logger.warning("Could not load initial state, skipping change detection")
            initial_state = {}

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        for tf in temp_files:
            if os.path.exists(tf):
                os.unlink(tf)

    score = 0
    feedback_parts = []
    
    # --- Check 1: Hotel Artemide Stars (25 pts) ---
    final_stars = str(results.get('final_artemide_stars', ''))
    # Allow "5" or "5.0"
    if final_stars in ['5', '5.0']:
        score += 25
        feedback_parts.append("Artemide Stars updated correctly")
    else:
        feedback_parts.append(f"Artemide Stars incorrect (expected 5, got {final_stars})")

    # --- Check 2: The Savoy Phone (25 pts) ---
    final_phone = str(results.get('final_savoy_phone', ''))
    expected_phone = "+44-20-7836-5555"
    if final_phone == expected_phone:
        score += 25
        feedback_parts.append("Savoy Phone updated correctly")
    else:
        feedback_parts.append(f"Savoy Phone incorrect (expected {expected_phone}, got {final_phone})")

    # --- Check 3: Copacabana Palace Type (25 pts) ---
    final_type = str(results.get('final_copacabana_type', ''))
    expected_type = "Palace"
    if final_type == expected_type:
        score += 25
        feedback_parts.append("Copacabana Type updated correctly")
    else:
        feedback_parts.append(f"Copacabana Type incorrect (expected {expected_type}, got {final_type})")

    # --- Check 4: Luca Rossi Surname (25 pts) ---
    final_surname = str(results.get('final_luca_surname', ''))
    expected_surname = "De Rossi"
    if final_surname == expected_surname:
        score += 25
        feedback_parts.append("Luca Rossi Surname updated correctly")
    else:
        feedback_parts.append(f"Luca Rossi Surname incorrect (expected {expected_surname}, got {final_surname})")

    # --- Anti-Gaming Checks ---
    # Check if records were deleted massively
    init_hotels = initial_state.get('hotel_count', 0)
    final_hotels = results.get('final_hotel_count', 0)
    
    if init_hotels > 0 and final_hotels < (init_hotels - 5):
        score = 0
        feedback_parts.append("FAIL: Significant data loss detected (Hotel count dropped)")

    # Check if value actually changed (if we have initial state)
    if initial_state:
        init_stars = str(initial_state.get('artemide_stars', ''))
        if init_stars == final_stars and score > 0:
             feedback_parts.append("WARNING: Artemide Stars did not change from initial state")

    passed = (score >= 50)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }