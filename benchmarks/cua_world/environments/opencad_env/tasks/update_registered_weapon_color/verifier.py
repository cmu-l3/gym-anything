#!/usr/bin/env python3
"""Verifier for update_registered_weapon_color task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_registered_weapon_color(traj, env_info, task_info):
    """
    Verify that the agent updated the weapon color to Pink.
    
    Criteria:
    1. Weapon with serial SM-9981 exists in DB (30 pts)
    2. Weapon color matches "Pink" (50 pts)
    3. Weapon is still owned by Sarah Mitchell (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_serial = metadata.get('target_serial', 'SM-9981')
    expected_color = metadata.get('expected_color', 'Pink').lower()
    expected_owner = metadata.get('target_owner', 'Sarah Mitchell').lower()
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/update_registered_weapon_color_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # Check 1: Weapon Found (30 pts)
    if result.get('weapon_found'):
        score += 30
        feedback_parts.append(f"Weapon {expected_serial} found")
    else:
        feedback_parts.append(f"Weapon {expected_serial} NOT found")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}
        
    weapon = result.get('weapon', {})
    
    # Check 2: Color matches Expected (50 pts)
    # We allow case-insensitive match
    actual_color = (weapon.get('color') or '').strip().lower()
    
    if actual_color == expected_color:
        score += 50
        feedback_parts.append(f"Color updated to {expected_color}")
    elif expected_color in actual_color:
        # Partial match (e.g. "Hot Pink")
        score += 40
        feedback_parts.append(f"Color partial match: {actual_color}")
    else:
        feedback_parts.append(f"Color mismatch: expected '{expected_color}', got '{actual_color}'")
        
    # Check 3: Owner Integrity (20 pts)
    # Ensure the agent didn't delete the user or assign the weapon to someone else
    actual_owner = (weapon.get('owner_name') or '').strip().lower()
    
    if expected_owner in actual_owner:
        score += 20
        feedback_parts.append("Owner verified")
    else:
        feedback_parts.append(f"Owner mismatch: expected '{expected_owner}', got '{actual_owner}'")
        
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }