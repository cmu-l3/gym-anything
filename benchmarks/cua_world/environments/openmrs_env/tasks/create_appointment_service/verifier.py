#!/usr/bin/env python3
"""
Verifier for create_appointment_service task.

Verifies that:
1. An Appointment Service Type named "Ergonomic Assessment" exists.
2. It has the correct duration (45 mins).
3. It has the correct description.
4. It was created AFTER the task started (anti-gaming).
5. It is active (not retired).
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_openmrs_date(date_str):
    """Parse OpenMRS ISO 8601 date string to timestamp."""
    if not date_str or date_str == 'null':
        return 0
    try:
        # Format: 2023-10-25T14:30:00.000+0000
        # Simplification: remove timezone or use just first 19 chars
        clean_date = date_str[:19]
        dt = datetime.strptime(clean_date, "%Y-%m-%dT%H:%M:%S")
        return dt.timestamp()
    except Exception as e:
        logger.warning(f"Failed to parse date {date_str}: {e}")
        return 0

def verify_create_appointment_service(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Ergonomic Assessment")
    expected_duration = metadata.get('expected_duration', 45)
    
    # Load result from container
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
    
    # Extract values
    service_found = result.get("service_found", False)
    actual_duration = result.get("service_duration", 0)
    description = result.get("service_description", "")
    date_created_iso = result.get("service_date_created_iso", "")
    task_start_ts = result.get("task_start_timestamp", 0)
    db_match_count = result.get("db_exact_match_count", 0)

    # 1. Service Existence (40 pts)
    if service_found:
        score += 40
        feedback.append(f"Service '{expected_name}' found.")
    else:
        feedback.append(f"Service '{expected_name}' NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Duration Check (30 pts)
    # We allow integer comparison
    if int(actual_duration) == int(expected_duration):
        score += 30
        feedback.append(f"Duration correct ({actual_duration} mins).")
    else:
        feedback.append(f"Duration mismatch: expected {expected_duration}, got {actual_duration}.")

    # 3. Description Check (10 pts)
    if "workplace evaluation" in description.lower():
        score += 10
        feedback.append("Description contains keywords.")
    else:
        feedback.append("Description missing expected keywords.")

    # 4. Anti-Gaming / Timestamp Check (10 pts)
    # Ensure creation time is after task start
    creation_ts = parse_openmrs_date(date_created_iso)
    if creation_ts > task_start_ts:
        score += 10
        feedback.append("Service created during task session.")
    else:
        feedback.append("Warning: Service appears to be created before task start.")

    # 5. DB Verification Cross-Check (10 pts)
    # If the SQL query confirmed an exact match of name+duration+active
    if int(db_match_count) > 0:
        score += 10
        feedback.append("Database verification confirmed exact record.")
    else:
        feedback.append("Database verification failed to find exact match (check parameters).")

    # Pass threshold
    # Must find service, have correct duration, and ideally be created during task
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }