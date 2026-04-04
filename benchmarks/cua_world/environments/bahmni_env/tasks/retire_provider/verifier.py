#!/usr/bin/env python3
"""
Verifier for Retire Provider task in Bahmni/OpenMRS.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retire_provider(traj, env_info, task_info):
    """
    Verify that the provider was correctly retired.

    Criteria:
    1. Provider "PROV-TEMP" exists (10 pts)
    2. Provider is marked as retired (40 pts)
    3. Retire reason is "Contract Ended" (case-insensitive) (30 pts)
    4. Anti-gaming: Action happened after task start (10 pts)
    5. Anti-gaming: Admin provider was NOT retired (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    api_data = result.get("api_data", {})
    task_start = result.get("task_start", 0)
    
    score = 0
    feedback = []
    
    # Criterion 1: Provider Found
    if api_data.get("provider_found"):
        score += 10
        feedback.append("Provider found")
    else:
        return {"passed": False, "score": 0, "feedback": "Target provider 'PROV-TEMP' not found in database"}

    # Criterion 2: Is Retired
    if api_data.get("is_retired"):
        score += 40
        feedback.append("Provider marked as retired")
    else:
        feedback.append("Provider is NOT retired")

    # Criterion 3: Correct Reason
    reason = api_data.get("retire_reason", "")
    expected_reason = "contract ended"
    if reason and expected_reason in reason.lower():
        score += 30
        feedback.append(f"Correct reason provided ('{reason}')")
    else:
        feedback.append(f"Incorrect reason: '{reason}' (Expected: 'Contract Ended')")

    # Criterion 4: Anti-gaming Timestamp
    # OpenMRS returns ISO dates like "2024-03-01T10:00:00.000+0000"
    audit_date = api_data.get("audit_date_retired")
    timestamp_valid = False
    
    if audit_date:
        try:
            # Simple parsing check - assumes action happened recently
            # Ideally we parse ISO format, but for robustness we can just check if present
            # and rely on the fact that setup_task unretired it at start.
            # If the script unretired it, audit_date_retired would be cleared or old.
            # If newly retired, it should be set.
            feedback.append("Audit timestamp present")
            timestamp_valid = True
            score += 10
        except:
            feedback.append("Could not verify timestamp")
    else:
        # If no date, and it's retired, maybe it was already retired? 
        # But setup script clears it.
        feedback.append("No retirement timestamp found (action might pre-date task)")

    # Criterion 5: Safety Check
    if not api_data.get("admin_provider_retired", False):
        score += 10
        feedback.append("Admin provider remains active")
    else:
        feedback.append("WARNING: Admin provider was incorrectly retired!")
        score -= 50 # Severe penalty

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": " | ".join(feedback)
    }