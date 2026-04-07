#!/usr/bin/env python3
"""Verifier for deregister_civilian_weapon task."""

import json
import tempfile
import os

def verify_deregister_civilian_weapon(traj, env_info, task_info):
    """
    Verify that the 'Combat Pistol' (DSL-882) was deleted and 'Pump Shotgun' (KEE-456) preserved.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_serial = metadata.get('target_serial', 'DSL-882')
    safe_serial = metadata.get('safe_serial', 'KEE-456')
    civ_name = metadata.get('civilian_name', 'Michael DeSanta')

    # Read result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/deregister_weapon_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Target Weapon is Gone (40 pts)
    # target_exists should be 0
    if result.get('target_exists', 1) == 0:
        score += 40
        feedback_parts.append(f"Target weapon ({target_serial}) successfully removed")
    else:
        feedback_parts.append(f"FAILURE: Target weapon ({target_serial}) still exists in database")

    # Check 2: Safe Weapon is Kept (30 pts)
    # safe_exists should be 1
    if result.get('safe_exists', 0) == 1:
        score += 30
        feedback_parts.append(f"Safe weapon ({safe_serial}) preserved")
    else:
        feedback_parts.append(f"FAILURE: Safe weapon ({safe_serial}) was wrongly deleted")

    # Check 3: Identity Preserved (10 pts)
    if result.get('identity_exists', 0) == 1:
        score += 10
        feedback_parts.append(f"Civilian identity ({civ_name}) preserved")
    else:
        feedback_parts.append(f"FAILURE: Civilian identity ({civ_name}) was deleted")

    # Check 4: Count Logic (20 pts)
    # Count should decrease by exactly 1
    initial = result.get('initial_count', 0)
    current = result.get('current_count', 0)
    
    if initial > 0 and current == initial - 1:
        score += 20
        feedback_parts.append("Weapon count decreased by exactly 1")
    elif current == initial:
        feedback_parts.append("Weapon count unchanged")
    else:
        feedback_parts.append(f"Unexpected count change: {initial} -> {current}")

    # Pass logic: Must have deleted target AND kept safe weapon
    passed = (result.get('target_exists') == 0) and (result.get('safe_exists') == 1)
    
    # Adjust score if logic failed but points added up via bugs
    if not passed and score >= 70:
        score = 69 

    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }