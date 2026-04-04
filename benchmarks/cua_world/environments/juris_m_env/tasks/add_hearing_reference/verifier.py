#!/usr/bin/env python3
"""
Verifier for add_hearing_reference task.

Criteria:
1. A "Hearing" item with "Watergate" in the title must exist.
2. Item must have been created during the task session (anti-gaming).
3. Metadata fields must match expectations (fuzzy match allowed for minor formatting).
"""

import os
import json
import logging
import tempfile
from datetime import datetime
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_hearing_reference(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "Phase I: Watergate Investigation")
    expected_committee = metadata.get('expected_committee', "Select Committee on Presidential Campaign Activities")
    expected_leg_body = metadata.get('expected_legislative_body', "U.S. Senate")
    expected_session = metadata.get('expected_session', "93rd Congress, 1st Session")
    expected_date = metadata.get('expected_date', "1973-05-17")
    expected_place = metadata.get('expected_place', "Washington, D.C.")
    expected_abstract_part = metadata.get('expected_abstract_snippet', "Hearings before the Select Committee")

    # Get result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for basic errors
    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"DB Error: {result['error']}"}

    score = 0
    feedback = []
    
    # 1. Check if item was found
    if not result.get('item_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No Hearing item with 'Watergate' in the title was found."
        }
    
    score += 10
    feedback.append("Hearing item created (+10)")
    
    # 2. Check anti-gaming (creation time)
    # SQLite dateAdded is usually "YYYY-MM-DD HH:MM:SS"
    item_date_str = result.get('item_details', {}).get('dateAdded', '')
    task_start_ts = result.get('task_start', 0)
    
    is_new = False
    if item_date_str:
        try:
            # Parse SQLite default format
            item_ts = datetime.strptime(item_date_str, "%Y-%m-%d %H:%M:%S").timestamp()
            # Allow some clock skew (e.g., 5 seconds)
            if item_ts >= (task_start_ts - 5):
                is_new = True
        except ValueError:
            # Fallback if format differs, though Jurism standard is predictable
            pass
            
    if is_new:
        score += 10
        feedback.append("Item created during task session (+10)")
    else:
        feedback.append("Warning: Item appears to be pre-existing (timestamps don't match task duration)")

    # 3. Verify Fields
    fields = result.get('item_details', {}).get('fields', {})
    
    def check_field(field_name, expected, points, actual_dict):
        # Jurism field names: title, legislativeBody, committee, session, date, place, abstractNote
        val = actual_dict.get(field_name, "")
        if not val:
            return 0, f"Missing {field_name}"
        
        # Normalize for fuzzy comparison (lowercase, remove punctuation)
        norm_val = "".join(c.lower() for c in val if c.isalnum())
        norm_exp = "".join(c.lower() for c in expected if c.isalnum())
        
        if norm_exp in norm_val or norm_val in norm_exp:
            return points, f"{field_name} correct"
        return 0, f"{field_name} mismatch (got '{val}', expected '{expected}')"

    # Title (Key: title)
    s, f = check_field('title', expected_title, 15, fields)
    score += s; feedback.append(f)
    
    # Committee (Key: committee)
    # Note: Sometimes mapped to 'seriesTitle' or 'publicationTitle' depending on exact schema version,
    # but 'committee' is the standard internal field name for Hearings.
    # We check 'committee' first, then 'publicationTitle' as fallback if committee is missing.
    if 'committee' in fields:
        s, f = check_field('committee', expected_committee, 15, fields)
    else:
        s, f = check_field('publicationTitle', expected_committee, 15, fields)
    score += s; feedback.append(f)

    # Legislative Body (Key: legislativeBody)
    s, f = check_field('legislativeBody', expected_leg_body, 15, fields)
    score += s; feedback.append(f)

    # Session (Key: session)
    s, f = check_field('session', expected_session, 10, fields)
    score += s; feedback.append(f)

    # Date (Key: date)
    s, f = check_field('date', expected_date, 10, fields)
    score += s; feedback.append(f)

    # Place (Key: place)
    s, f = check_field('place', expected_place, 10, fields)
    score += s; feedback.append(f)

    # Abstract (Key: abstractNote)
    s, f = check_field('abstractNote', expected_abstract_part, 5, fields)
    score += s; feedback.append(f)

    # Final Score Calculation
    passed = (score >= 60) and result.get('item_found')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }