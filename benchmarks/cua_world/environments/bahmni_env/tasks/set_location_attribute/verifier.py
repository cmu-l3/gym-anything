#!/usr/bin/env python3
"""
Verifier for set_location_attribute task.

Checks:
1. "Satellite Clinic" location exists.
2. It has an active (not voided) attribute of type "Facility Code".
3. The value is exactly "FAC-8829".
4. The attribute was created or modified AFTER the task started (anti-gaming).
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_openmrs_date(date_str):
    """Parse OpenMRS ISO 8601 date string (e.g., 2023-10-25T14:30:00.000+0000)."""
    if not date_str:
        return 0
    try:
        # Python 3.7+ handles ISO 8601 with timezone, but OpenMRS format might need adjustment
        # Removing the last colon in offset if present might be needed for older python, 
        # but standardized format usually works. 
        # Simpler approach: parse first 19 chars (YYYY-MM-DDTHH:MM:SS) if timezone is annoying
        dt = datetime.strptime(date_str.split('.')[0], "%Y-%m-%dT%H:%M:%S")
        return dt.timestamp()
    except Exception as e:
        logger.warning(f"Failed to parse date {date_str}: {e}")
        return 0

def verify_set_location_attribute(traj, env_info, task_info):
    """
    Verify that the location attribute was set correctly via API data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values
    metadata = task_info.get('metadata', {})
    expected_val = metadata.get('expected_value', 'FAC-8829')

    try:
        # Copy result JSON
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)

        feedback_parts = []
        score = 0
        
        # 1. Location Existence (20 pts)
        loc_uuid = result.get('location_uuid')
        if loc_uuid:
            score += 20
            feedback_parts.append("Location 'Satellite Clinic' found.")
        else:
            return {"passed": False, "score": 0, "feedback": "Location 'Satellite Clinic' not found."}

        # 2. Attribute Existence and Value (50 pts)
        attr_data = result.get('attribute_data', {})
        if not attr_data.get('found'):
            return {
                "passed": False, 
                "score": score, 
                "feedback": " | ".join(feedback_parts) + " | 'Facility Code' attribute not found on location."
            }
        
        actual_val = attr_data.get('value')
        if actual_val == expected_val:
            score += 50
            feedback_parts.append(f"Attribute value correct: '{actual_val}'.")
        else:
            feedback_parts.append(f"Attribute value mismatch. Expected '{expected_val}', got '{actual_val}'.")
            # Partial credit if they created the attribute but wrong value
            score += 10 

        # 3. Not Voided (10 pts)
        if not attr_data.get('voided'):
            score += 10
            feedback_parts.append("Attribute is active.")
        else:
            feedback_parts.append("Attribute is voided (deleted).")

        # 4. Anti-gaming / Timestamp Check (20 pts)
        # Ensure the attribute was actually created/modified during this session
        task_start = result.get('task_start', 0)
        
        date_created_str = attr_data.get('dateCreated')
        date_changed_str = attr_data.get('dateChanged')
        
        ts_created = parse_openmrs_date(date_created_str)
        ts_changed = parse_openmrs_date(date_changed_str)
        
        # Allow a small buffer for clock skew if needed, but usually same container
        latest_mod = max(ts_created, ts_changed)
        
        if latest_mod > task_start:
            score += 20
            feedback_parts.append("Attribute modified during task session.")
        else:
            feedback_parts.append("Attribute modification timestamp is before task start (pre-existing?).")
            # Deduct points significantly if it seems pre-existing
            score = min(score, 30) # Cap score for pre-existing data

        passed = (score >= 90) # Requires almost perfect execution

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Verification error")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {str(e)}"}