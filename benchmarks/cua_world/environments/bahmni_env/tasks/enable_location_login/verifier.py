#!/usr/bin/env python3
"""
Verifier for Enable Location Login task.

Checks:
1. Location "Telemedicine Wing" exists and is active (not retired).
2. Location has "Login Location" tag (Required for login screen).
3. Location has "Visit Location" tag (Required for visits).
4. Anti-gaming: Verifies the location was modified AFTER the task started.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_openmrs_date(date_str):
    """Parse OpenMRS ISO8601 date string to timestamp."""
    if not date_str:
        return 0
    try:
        # Example: 2023-10-27T10:00:00.000+0000
        # Python 3.7+ handles ISO formats fairly well, but +0000 might need handling if strictly checking
        # Simplification: strip timezone or use dateutil if available. 
        # Standard lib usually likes: 2023-10-27T10:00:00.000+00:00
        # We'll do a basic parse.
        dt = datetime.strptime(date_str.split('+')[0], "%Y-%m-%dT%H:%M:%S.%f")
        return dt.timestamp()
    except ValueError:
        try:
             # Try without micros
             dt = datetime.strptime(date_str.split('+')[0], "%Y-%m-%dT%H:%M:%S")
             return dt.timestamp()
        except:
            return 0

def verify_enable_location_login(traj, env_info, task_info):
    """Verify the location configuration task."""
    
    # 1. Setup Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve Result Data
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

    # 3. Parse Data
    api_data = result.get('api_data', {})
    task_start = result.get('task_start', 0)
    
    location_found = api_data.get('location_found', False)
    retired = api_data.get('retired', True)
    tags = api_data.get('tags', [])
    date_changed_str = api_data.get('date_changed')
    
    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Location Existence (20 pts)
    if location_found and not retired:
        score += 20
        feedback_parts.append("Location 'Telemedicine Wing' is active.")
    elif location_found and retired:
        feedback_parts.append("Location found but is RETIRED (inactive).")
    else:
        return {"passed": False, "score": 0, "feedback": "Location 'Telemedicine Wing' not found."}

    # Criterion 2: 'Login Location' Tag (40 pts)
    # Flexible matching for tag names
    has_login_tag = any("login location" in t.lower() for t in tags)
    if has_login_tag:
        score += 40
        feedback_parts.append("Has 'Login Location' tag.")
    else:
        feedback_parts.append("Missing 'Login Location' tag.")

    # Criterion 3: 'Visit Location' Tag (40 pts)
    has_visit_tag = any("visit location" in t.lower() for t in tags)
    if has_visit_tag:
        score += 40
        feedback_parts.append("Has 'Visit Location' tag.")
    else:
        feedback_parts.append("Missing 'Visit Location' tag.")

    # Anti-Gaming Check: Modification Time
    # If the location wasn't modified during the task, the agent probably didn't do anything
    # (or we are looking at a stale state).
    # Note: If date_changed is None, check date_created (maybe they deleted and recreated it)
    mod_timestamp = parse_openmrs_date(date_changed_str)
    
    # Allow a small buffer (e.g., 60s) for clock skew
    if mod_timestamp > (task_start - 60):
        feedback_parts.append("Configuration modified during task.")
    else:
        # Penalize if it looks like nothing changed, but be careful of false positives.
        # If score is 100 but timestamp is old, it's suspicious (pre-configured env?)
        # Since setup clears tags, if tags are present, *someone* added them. 
        # So we trust the state over the timestamp if state is correct, but add a warning.
        if score == 100:
            feedback_parts.append("(Warning: Modification timestamp is old, but state is correct)")
        else:
            feedback_parts.append("(No modification detected during task)")

    # 5. Final Verdict
    # Pass requires essentially full score (both tags needed for functional requirement)
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }