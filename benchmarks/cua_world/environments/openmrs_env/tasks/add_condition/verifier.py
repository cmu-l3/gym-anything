#!/usr/bin/env python3
"""
Verifier for add_condition task (OpenMRS).
Verifies that 'Asthma' was added as an Active condition.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_openmrs_date(date_str):
    """Parses OpenMRS ISO8601 date string to timestamp."""
    try:
        # Example: 2023-10-27T10:00:00.000+0000
        # Removing timezone offset for simple comparison if needed, or handle properly
        if '+' in date_str:
            dt = datetime.strptime(date_str.split('+')[0], "%Y-%m-%dT%H:%M:%S.%f")
        elif 'Z' in date_str:
             dt = datetime.strptime(date_str.replace('Z', ''), "%Y-%m-%dT%H:%M:%S.%f")
        else:
            return 0
        return dt.timestamp()
    except Exception as e:
        logger.warning(f"Failed to parse date {date_str}: {e}")
        return 0

def verify_add_condition(traj, env_info, task_info):
    """
    Verifies the add_condition task.
    
    Criteria:
    1. Asthma condition exists for patient (40 pts)
    2. Status is 'Active' (20 pts)
    3. Condition was created *after* task start (Anti-gaming) (20 pts)
    4. Condition count increased (Verification of new data) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result JSON
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

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # Data from result
    asthma_found = result.get('asthma_found', False)
    asthma_status = result.get('asthma_status', '').lower()
    date_created_iso = result.get('date_created_iso', '')
    task_start_ts = result.get('task_start_ts', 0)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)

    # Criterion 1: Asthma Found (40 pts)
    if asthma_found:
        score += 40
        feedback_parts.append("Asthma condition found.")
    else:
        feedback_parts.append("Asthma condition NOT found.")

    # Criterion 2: Status is Active (20 pts)
    if asthma_found:
        if 'active' in asthma_status:
            score += 20
            feedback_parts.append("Status is Active.")
        else:
            feedback_parts.append(f"Status is '{asthma_status}' (expected 'Active').")
    
    # Criterion 3: Anti-gaming (Created during task) (20 pts)
    created_during_task = False
    if asthma_found and date_created_iso:
        created_ts = parse_openmrs_date(date_created_iso)
        # Allow small clock skew/tolerance (e.g. 10 seconds before start if containers slightly out of sync, usually not needed)
        if created_ts >= (task_start_ts - 5):
            score += 20
            created_during_task = True
            feedback_parts.append("Condition created during task.")
        else:
            feedback_parts.append("Condition timestamp predates task start (pre-existing data?).")
    elif asthma_found:
        feedback_parts.append("Could not verify creation timestamp.")

    # Criterion 4: Count check (20 pts)
    if current_count > initial_count:
        score += 20
        feedback_parts.append("Total condition count increased.")
    else:
        feedback_parts.append("Total condition count did not increase.")

    # Pass logic
    # Must have found asthma, active, and created during task to pass reliably
    passed = (score >= 80) and created_during_task

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }