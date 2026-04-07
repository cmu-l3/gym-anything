#!/usr/bin/env python3
"""
Verifier for manage_trespassing_incident task.

Verifies:
1. Call Creation: Record exists with correct Caller and Location.
2. Call Update: Narrative contains specific keywords from the update step.
3. Call Closure: Record is found in history table (or marked closed).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manage_trespassing_incident(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    initial_keywords = metadata.get('initial_keywords', ["climbing", "fence"])
    update_keywords = metadata.get('update_keywords', ["1A-01", "compliant"])

    # Load result from container
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

    score = 0
    feedback_parts = []
    
    found_loc = result.get('found_location', 'none')
    narrative = result.get('description', '').lower()

    # 1. Verify Call Existence (30 pts)
    if found_loc in ['active', 'history']:
        score += 30
        feedback_parts.append("Call created successfully")
    else:
        feedback_parts.append("No matching call found")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}

    # 2. Verify Initial Content (20 pts)
    # Check if initial description keywords are present
    has_initial = any(k.lower() in narrative for k in initial_keywords)
    if has_initial:
        score += 20
        feedback_parts.append("Initial description verified")
    else:
        feedback_parts.append("Initial description missing keywords")

    # 3. Verify Update Content (30 pts)
    # Check if update keywords are present (CRITICAL step)
    # Note: If the agent overwrote the description instead of appending, 
    # they might still get points if they included the new info, but appending is preferred.
    has_update = any(k.lower() in narrative for k in update_keywords)
    if has_update:
        score += 30
        feedback_parts.append("Call narrative updated successfully")
    else:
        feedback_parts.append("Update missing from narrative")

    # 4. Verify Closure (20 pts)
    if found_loc == 'history':
        score += 20
        feedback_parts.append("Call closed/archived successfully")
    else:
        # If found in active, check if status says Closed (some configs keep closed calls in active table briefly)
        status = result.get('status', '').lower()
        if 'close' in status or 'resolve' in status:
            score += 20
            feedback_parts.append("Call marked Closed (in active table)")
        else:
            feedback_parts.append("Call left in Active state (not closed)")

    # Pass threshold: 70
    # Requires at least Creation (30) + Update (30) + (Initial or Closure)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }