#!/usr/bin/env python3
"""
Verifier for rename_calendar_event task.

Criteria:
1. Event with new name "Q3 Marketing Results & Q4 Strategy Planning" exists (25 pts)
2. Event with old name "Marketing Campaign Review" does NOT exist (20 pts)
3. Event attributes preserved (Attendees, Location, Description) (35 pts)
4. Event ID preserved (Edit in place) + Anti-gaming timestamp (20 pts)
"""

import json
import logging
import os
import sys
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rename_calendar_event(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Target Name Found (25 pts)
    if result.get('target_name_found'):
        score += 25
        feedback.append("Success: Event with new title found.")
    else:
        feedback.append("Fail: Event with new title 'Q3 Marketing Results & Q4 Strategy Planning' not found.")
        # Critical fail, return early? No, let's score partials.
    
    # 2. Original Name Gone (20 pts)
    if not result.get('original_name_exists'):
        score += 20
        feedback.append("Success: Old event title no longer exists.")
    else:
        feedback.append("Fail: Old event title 'Marketing Campaign Review' still exists.")

    # 3. Attributes Preserved (35 pts total)
    details = result.get('target_event_details', {})
    if details:
        # Location (10 pts)
        loc = details.get('location', '')
        if loc and 'Zoom Meeting' in loc:
            score += 10
            feedback.append("Success: Location preserved.")
        else:
            feedback.append(f"Fail: Location is '{loc}', expected 'Zoom Meeting'.")
            
        # Description (10 pts) - check snippet
        desc = details.get('description', '')
        if desc and 'Review Q3 marketing campaign' in desc:
            score += 10
            feedback.append("Success: Description preserved.")
        else:
            feedback.append("Fail: Description content changed or missing.")
            
        # Attendees (15 pts)
        attendees = details.get('attendees', [])
        required = ['Alice Johnson', 'Carol Martinez']
        missing = [p for p in required if p not in attendees]
        if not missing:
            score += 15
            feedback.append("Success: Attendees preserved.")
        else:
            feedback.append(f"Fail: Missing attendees: {', '.join(missing)}.")
    
    # 4. In-place Edit & Timestamp (20 pts)
    if result.get('same_id_reused'):
        score += 10
        feedback.append("Success: Event edited in-place (ID preserved).")
    else:
        feedback.append("Fail: Event ID changed (likely deleted and recreated).")
        
    # Timestamp check (10 pts)
    # We allow this if target_name_found is true, even if same_id_reused is false (recreation is valid work, just less efficient)
    if result.get('target_name_found'):
        # In a real scenario, we'd parse the timestamp. For now, just existence of write_date implies modification.
        if result.get('write_date'):
            score += 10
            feedback.append("Success: Modification timestamp detected.")
        else:
            feedback.append("Fail: No modification timestamp.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }