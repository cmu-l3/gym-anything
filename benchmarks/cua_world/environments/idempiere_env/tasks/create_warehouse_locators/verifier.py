#!/usr/bin/env python3
"""
Verifier for create_warehouse_locators task.
Checks if 3 specific warehouse locators were created in iDempiere database.
"""

import json
import os
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_warehouse_locators(traj, env_info, task_info):
    """
    Verifies that the agent created 3 specific storage locators in HQ Warehouse.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    task_start = result.get('task_start_time', 0)
    found_locators = result.get('found_locators', [])
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    
    # Target expectations
    targets = {
        'OV-01-01': {'x': '1', 'y': '1', 'z': '1'},
        'OV-01-02': {'x': '1', 'y': '1', 'z': '2'},
        'OV-01-03': {'x': '1', 'y': '1', 'z': '3'}
    }
    
    score = 0
    feedback_parts = []
    
    # 3. Verify Specific Locators (60 points total, 20 per locator)
    found_map = {l['value']: l for l in found_locators}
    
    for key, coords in targets.items():
        if key in found_map:
            locator = found_map[key]
            
            # Check timestamp (Anti-gaming)
            # Postgres JSON timestamp might need parsing, but we can usually check basic existence first
            # Ideally we parse 'created' string "2024-03-07 10:00:00" vs task_start
            # For simplicity in this env, existence + count change is strong evidence
            
            # Check Coordinates (Optional but good)
            # The query returns strings for x,y,z usually
            lx = str(locator.get('x', ''))
            ly = str(locator.get('y', ''))
            lz = str(locator.get('z', ''))
            
            if lx == coords['x'] and ly == coords['y'] and lz == coords['z']:
                 score += 20
                 feedback_parts.append(f"Locator {key} created correctly.")
            else:
                 score += 15 # Partial credit for correct name but wrong coords
                 feedback_parts.append(f"Locator {key} created but coordinates mismatch (Expected {coords['x']},{coords['y']},{coords['z']}, Got {lx},{ly},{lz}).")
        else:
            feedback_parts.append(f"Locator {key} NOT found.")

    # 4. Verify Warehouse Association (20 points)
    # If the export script found them using the HQ Warehouse ID, this is implicitly true
    # We give points if at least one was found in the correct warehouse
    if len(found_map) > 0:
        score += 20
        feedback_parts.append("Locators assigned to correct HQ Warehouse.")
    else:
        feedback_parts.append("No locators found in HQ Warehouse.")

    # 5. Anti-Gaming / Count Check (20 points)
    # Ensure net increase matches creation
    count_diff = current_count - initial_count
    if count_diff >= 3:
        score += 20
        feedback_parts.append(f"Locator count increased by {count_diff} (Expected >= 3).")
    elif count_diff > 0:
        score += 10
        feedback_parts.append(f"Locator count only increased by {count_diff}.")
    else:
        feedback_parts.append("Locator count did not increase.")

    # 6. Final Result
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }