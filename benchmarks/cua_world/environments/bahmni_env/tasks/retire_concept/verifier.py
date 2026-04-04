#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retire_concept(traj, env_info, task_info):
    """
    Verifies that the concept was retired with the correct reason.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Scoring configuration
    score = 0
    feedback_parts = []
    
    # 1. Check if concept was found
    if not result.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target concept 'Duplicate Diagnosis Code' could not be found in the system."
        }
    
    # 2. Check if retired (50 pts)
    is_retired = result.get('retired', False)
    if is_retired:
        score += 50
        feedback_parts.append("Concept is retired")
    else:
        feedback_parts.append("Concept is NOT retired")

    # 3. Check retire reason (20 pts)
    # Expected: "Administrative cleanup"
    retire_reason = result.get('retireReason', '') or ''
    if "administrative" in retire_reason.lower() and "cleanup" in retire_reason.lower():
        score += 20
        feedback_parts.append(f"Retire reason correct ('{retire_reason}')")
    elif retire_reason:
        score += 10
        feedback_parts.append(f"Retire reason present but imprecise ('{retire_reason}')")
    else:
        feedback_parts.append("No retire reason provided")

    # 4. Anti-gaming: Check timestamps (20 pts)
    # OpenMRS ISO Format: "2024-05-20T10:30:00.000+0000"
    audit_info = result.get('auditInfo', {})
    date_retired_str = audit_info.get('dateRetired')
    task_start_ts = result.get('task_start', 0)
    
    timestamp_valid = False
    if date_retired_str and is_retired:
        try:
            # Handle variable millisecond precision if needed, but standard strptime usually strictly matches
            # Python < 3.11 doesn't handle 'Z' or offsets nicely without third party libs sometimes, 
            # but OpenMRS sends +0000.
            # Simplified parsing:
            dt_str = date_retired_str.split('+')[0].split('.')[0] # Strip timezone and millis for rough comparison
            retired_ts = datetime.strptime(dt_str, "%Y-%m-%dT%H:%M:%S").timestamp()
            
            # Allow small clock skew (e.g. 10s)
            if retired_ts >= (task_start_ts - 10):
                timestamp_valid = True
                score += 20
                feedback_parts.append("Modification occurred during task session")
            else:
                feedback_parts.append("Concept was retired before task started")
        except Exception as e:
            logger.warning(f"Failed to parse timestamp {date_retired_str}: {e}")
            feedback_parts.append("Could not verify modification timestamp")
    elif is_retired:
         feedback_parts.append("No dateRetired timestamp found")

    # 5. User check (10 pts)
    retired_by = audit_info.get('retiredBy', {}).get('display', '')
    # Usually "Super Man" or "admin" depending on setup
    if retired_by:
        score += 10
        feedback_parts.append(f"Action performed by {retired_by}")

    # Determine pass/fail
    # Must be retired AND (valid reason OR valid timestamp)
    # Threshold 70 means basically everything must be right
    passed = (score >= 70) and is_retired

    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }