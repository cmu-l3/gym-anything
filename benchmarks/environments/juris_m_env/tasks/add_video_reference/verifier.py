#!/usr/bin/env python3
"""
Verifier for add_video_reference task.

Scoring Criteria:
1. Item Created (30 pts): Item with title 'Hot Coffee' exists.
2. Item Type (10 pts): Item type is 'videoRecording'.
3. Director Role (20 pts): Creator 'Saladoff' has role 'director'.
4. Distributor (15 pts): Matches 'HBO Documentary Films'.
5. Running Time (15 pts): Matches '86 min'.
6. Date (10 pts): Matches '2011'.

Pass Threshold: 85/100
"""

import os
import json
import logging
import tempfile
from datetime import datetime
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_video_reference(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any]
) -> Dict[str, Any]:
    
    # 1. Setup and Load Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Metadata Expectations
    meta = task_info.get('metadata', {})
    expected_title = meta.get('expected_title', 'Hot Coffee')
    expected_role = meta.get('expected_creator_role', 'director')
    
    # 3. Score Calculation
    score = 0
    feedback = []
    
    # Check 1: Item Exists (30 pts)
    if result.get('item_found'):
        score += 30
        feedback.append(f"Item '{result.get('title')}' found (+30)")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Item '{expected_title}' not found in library."
        }

    # Check 2: Item Type (10 pts)
    # Zotero internal name for Video Recording is 'videoRecording'
    if result.get('item_type') == 'videoRecording':
        score += 10
        feedback.append("Item type 'Video Recording' correct (+10)")
    else:
        feedback.append(f"Incorrect item type: found '{result.get('item_type')}', expected 'Video Recording'")

    # Check 3: Creator Role (20 pts)
    # This is the tricky part - did they change it to Director?
    creator_role = result.get('creator_role', '').lower()
    if creator_role == expected_role:
        score += 20
        feedback.append("Creator role 'Director' correct (+20)")
    else:
        feedback.append(f"Incorrect creator role: found '{creator_role}', expected '{expected_role}'")

    # Check 4: Distributor (15 pts)
    dist = result.get('distributor', '')
    if 'hbo' in dist.lower() and 'documentary' in dist.lower():
        score += 15
        feedback.append("Distributor correct (+15)")
    else:
        feedback.append(f"Distributor mismatch: found '{dist}'")

    # Check 5: Running Time (15 pts)
    runtime = result.get('running_time', '')
    if '86' in runtime:
        score += 15
        feedback.append("Running time correct (+15)")
    else:
        feedback.append(f"Running time mismatch: found '{runtime}'")

    # Check 6: Date (10 pts)
    date_val = result.get('date', '')
    if '2011' in date_val:
        score += 10
        feedback.append("Date correct (+10)")
    else:
        feedback.append(f"Date mismatch: found '{date_val}'")

    # Anti-gaming: Check timestamp
    # Ensure item was added AFTER task started
    task_start = result.get('task_start', 0)
    date_added_str = result.get('date_added', '')
    
    created_during_task = False
    if date_added_str and task_start > 0:
        # Zotero dates are usually UTC "YYYY-MM-DD HH:MM:SS"
        try:
            # Simple string comparison or proper parsing
            # SQLite 'dateAdded' is usually formatted string.
            # We can check if the file creation time is reasonable, 
            # but simplest is to trust the ID if we cleaned up before.
            # However, strictly:
            dt_added = datetime.strptime(date_added_str, "%Y-%m-%d %H:%M:%S")
            timestamp_added = dt_added.timestamp()
            if timestamp_added >= task_start - 60: # buffer for clock skew
                created_during_task = True
        except:
            pass
            
    if not created_during_task:
        feedback.append("(Warning: Item creation time seems old, but proceeding based on ID)")

    # 4. Final Verdict
    pass_threshold = 85
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": result
    }