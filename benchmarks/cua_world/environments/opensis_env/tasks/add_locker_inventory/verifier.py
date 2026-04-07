#!/usr/bin/env python3
"""
Verifier for add_locker_inventory task.

Verifies:
1. Locker records exist in database
2. Combinations match expected values
3. Records were created during the task (locker_id check)
4. Location is correct
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_locker_inventory(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected data from metadata
    expected_lockers = task_info.get('metadata', {}).get('lockers', [])
    if not expected_lockers:
        # Fallback defaults if metadata missing
        expected_lockers = [
            {"number": "N-100", "combination": "12-34-56", "location": "North Hall"},
            {"number": "N-101", "combination": "25-10-45", "location": "North Hall"},
            {"number": "N-102", "combination": "00-11-22", "location": "North Hall"}
        ]

    # Retrieve result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    found_lockers = result.get('found_lockers', [])
    initial_max_id = result.get('initial_max_id', 0)
    
    score = 0
    feedback = []
    
    # Helper to find a locker in the results
    def find_locker(num):
        for l in found_lockers:
            if l.get('locker_number') == num:
                return l
        return None

    # Verify each expected locker
    for exp in expected_lockers:
        num = exp['number']
        combo = exp['combination']
        loc = exp['location']
        
        actual = find_locker(num)
        
        if actual:
            # 1. Existence (20 pts)
            score += 20
            fb_str = f"Locker {num}: Found."
            
            # 2. Combination check (10 pts)
            if actual.get('combination') == combo:
                score += 10
                fb_str += " Combo correct."
            else:
                fb_str += f" Combo mismatch (exp: {combo}, got: {actual.get('combination')})."

            # 3. Location/Details check (approx 3.3 pts distributed, we'll just verify location for full credit logic)
            # The original plan gave 10 pts for location generally. Let's add 3 pts per locker for location
            if actual.get('location') == loc:
                score += 3
                fb_str += " Location correct."
            else:
                fb_str += f" Location mismatch (exp: {loc}, got: {actual.get('location')})."
                
            # 4. Anti-gaming: ID check
            lid = actual.get('locker_id', 0)
            if lid > initial_max_id:
                fb_str += " (New record confirmed)."
            else:
                score -= 20 # Penalize if it's an old record (though setup script should have deleted them)
                fb_str += " (WARNING: Old record ID)."

            feedback.append(fb_str)
        else:
            feedback.append(f"Locker {num}: NOT FOUND.")

    # Normalize score (Max possible with above logic: 3 * (20 + 10 + 3) = 99. Close enough to 100)
    # Let's just cap at 100
    if score > 100: score = 100
    
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }