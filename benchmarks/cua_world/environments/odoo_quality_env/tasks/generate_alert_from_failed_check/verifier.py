#!/usr/bin/env python3
"""
Verifier for generate_alert_from_failed_check task.

Criteria:
1. Alert Created: A quality alert exists linked to the specific failed check.
2. Linkage: The alert is linked to the correct source check ID.
3. Content: Title matches "Cabinet Structural Defect".
4. Content: Tags include "Structural".
5. Anti-gaming: Alert was created after task start.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_alert_from_failed_check(traj, env_info, task_info):
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

    # Task Metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "Cabinet Structural Defect").lower()
    expected_tag = metadata.get('expected_tag', "Structural").lower()

    # Evaluation
    score = 0
    feedback = []
    
    # Check 1: Basic Existence & Linkage (Target check found and has alert)
    if not result.get("check_found"):
        return {"passed": False, "score": 0, "feedback": "Target quality check could not be found in database."}

    if result.get("alert_linked") and result.get("alert_created"):
        score += 30
        feedback.append("Alert created and linked to correct check.")
    else:
        feedback.append("No alert linked to the specific failed check.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Check 2: Timestamp (Anti-gaming)
    # The export script filters for this, but let's double check if it passed a valid alert
    if result.get("alert_create_date_timestamp", 0) > 0:
        score += 10
        feedback.append("Alert created during task.")
    else:
        # If export script returned an alert but timestamp was old (shouldn't happen with export logic, but safety)
        feedback.append("Linked alert appears to be old.")

    # Check 3: Title Accuracy
    actual_title = (result.get("alert_title") or "").strip().lower()
    if actual_title == expected_title:
        score += 30
        feedback.append(f"Title matches exactly: '{result.get('alert_title')}'.")
    elif expected_title in actual_title:
        score += 20
        feedback.append(f"Title contains expected text but not exact match ('{result.get('alert_title')}').")
    else:
        feedback.append(f"Title incorrect. Expected '{expected_title}', got '{actual_title}'.")

    # Check 4: Tag Accuracy
    actual_tags = [t.lower() for t in result.get("alert_tags", [])]
    if expected_tag in actual_tags:
        score += 30
        feedback.append(f"Tag '{expected_tag}' found.")
    else:
        feedback.append(f"Tag '{expected_tag}' missing. Found: {result.get('alert_tags')}.")

    # Final Calculation
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }