#!/usr/bin/env python3
"""
Verifier for add_concept_to_set task.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_openmrs_date(date_str):
    """Parse OpenMRS date string to timestamp."""
    if not date_str:
        return 0
    try:
        # Example: 2024-12-15T14:30:00.000+0000
        # Simplification: Ignore timezone for comparison if running locally, or strip
        clean_str = date_str.split('+')[0].split('.')[0]
        dt = datetime.strptime(clean_str, "%Y-%m-%dT%H:%M:%S")
        return dt.timestamp()
    except Exception as e:
        logger.warning(f"Date parse error: {e}")
        return 0

def verify_add_concept_to_set(traj, env_info, task_info):
    """
    Verify that Serum Magnesium was added to Electrolytes Panel.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    api_result = result.get("api_result", {})
    task_start = result.get("task_start", 0)
    
    score = 0
    feedback = []

    # 1. Check membership (Primary Goal) - 60 pts
    magnesium_in_set = api_result.get("magnesium_in_set", False)
    if magnesium_in_set:
        score += 60
        feedback.append("Serum Magnesium successfully added to Electrolytes Panel.")
    else:
        feedback.append("Serum Magnesium NOT found in Electrolytes Panel.")

    # 2. Check panel existence and valid UUIDs - 20 pts
    panel_exists = api_result.get("panel_exists", False)
    if panel_exists:
        score += 20
    else:
        feedback.append("Target panel concept not found (deleted?).")

    # 3. Anti-gaming: Check modification time - 10 pts
    date_changed_str = api_result.get("date_changed")
    last_modified = parse_openmrs_date(date_changed_str)
    
    # Allow 5 second buffer for clock skew
    if magnesium_in_set and last_modified > (task_start - 5):
        score += 10
        feedback.append("Modification occurred during task session.")
    elif magnesium_in_set:
        feedback.append("WARNING: Concept modified before task start (stale state?).")
    
    # 4. App running - 10 pts
    if result.get("app_running", False):
        score += 10
    
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }