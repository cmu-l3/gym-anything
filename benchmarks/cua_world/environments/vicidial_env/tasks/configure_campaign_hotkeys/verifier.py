#!/usr/bin/env python3
"""
Verifier for configure_campaign_hotkeys task.

Criteria:
1. Campaign 'RAPID' exists (10 pts)
2. Campaign is Active (5 pts)
3. Allow Closers is Y (5 pts) - (Added based on description, though not in original rationale, it's good practice)
4. HotKeys Active is Y (15 pts)
5. Correct HotKey Mappings (15 pts each for 1, 3, 8, 9)
6. No extra keys (5 pts)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_campaign_hotkeys(traj, env_info, task_info):
    """
    Verifies the Vicidial campaign configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_hotkeys = metadata.get('required_hotkeys', {
        "1": "SALE",
        "3": "DNC",
        "8": "CALLBK",
        "9": "NI"
    })

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Verify Campaign Exists
    if not result.get('campaign_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Campaign 'RAPID' was not found in the database."
        }
    
    score += 10
    feedback.append("Campaign 'RAPID' created.")
    
    camp_data = result.get('campaign_data', {})
    
    # 2. Verify Campaign Settings
    # Active
    if camp_data.get('active') == 'Y':
        score += 5
        feedback.append("Campaign is Active.")
    else:
        feedback.append("Campaign is NOT Active.")

    # Allow Closers (part of desc)
    if camp_data.get('allow_closers') == 'Y':
        score += 5
        feedback.append("Allow Closers is enabled.")
    else:
        feedback.append("Allow Closers is NOT enabled.")

    # HotKeys Active
    if camp_data.get('hotkeys_active') == 'Y':
        score += 15
        feedback.append("HotKeys are enabled.")
    else:
        feedback.append("HotKeys are NOT enabled (hotkeys_active != Y).")

    # 3. Verify HotKey Mappings
    actual_hotkeys_list = result.get('hotkeys', [])
    actual_hotkeys_map = {item['hotkey']: item['status'] for item in actual_hotkeys_list}
    
    keys_score = 0
    for key, expected_status in expected_hotkeys.items():
        actual_status = actual_hotkeys_map.get(key)
        if actual_status == expected_status:
            keys_score += 15
            feedback.append(f"Key '{key}' mapped correctly to '{expected_status}'.")
        elif actual_status:
            feedback.append(f"Key '{key}' mapped incorrectly (expected '{expected_status}', got '{actual_status}').")
        else:
            feedback.append(f"Key '{key}' NOT mapped.")
    
    score += keys_score

    # 4. Check for extra keys
    # We expect exactly len(expected_hotkeys)
    if len(actual_hotkeys_list) == len(expected_hotkeys):
        score += 5
        feedback.append("No extra hotkeys defined.")
    elif len(actual_hotkeys_list) > len(expected_hotkeys):
        feedback.append(f"Found {len(actual_hotkeys_list)} hotkeys, expected {len(expected_hotkeys)}. Penalized for extra keys.")
    else:
        # If fewer, they lost points above, so we don't double penalize, 
        # but we don't give the "perfect set" bonus.
        pass

    # 5. VLM / Trajectory Verification (Secondary)
    # Since this is a pure config task, DB verification is definitive.
    # However, we can check if the score is high enough to imply success.

    passed = score >= 60 and camp_data.get('hotkeys_active') == 'Y'

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }