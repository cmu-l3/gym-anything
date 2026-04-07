#!/usr/bin/env python3
"""
Verifier for implement_blocked_status_workflow task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_blocked_status_workflow(traj, env_info, task_info):
    """
    Verifies the task based on the JSON exported from the container.
    
    Scoring:
    - Status 'On Hold' created: 30 pts
    - Workflow configured correctly: 20 pts
    - Work Package updated to 'On Hold': 50 pts
    - Integrity Check (didn't destroy 'New'): Required for passing
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse internal verification data
    internal = data.get("internal_verification", {})
    details = internal.get("details", [])
    
    status_created = internal.get("status_created", False)
    workflow_configured = internal.get("workflow_configured", False)
    wp_updated = internal.get("wp_updated", False)
    integrity_check = internal.get("integrity_check", True)

    score = 0
    feedback = []

    # Criterion 1: Status Creation (30 pts)
    if status_created:
        score += 30
        feedback.append("Success: Status 'On Hold' created.")
    else:
        feedback.append("Fail: Status 'On Hold' not found.")

    # Criterion 2: Workflow Configuration (20 pts)
    if workflow_configured:
        score += 20
        feedback.append("Success: Workflow transition configured for Developer/Bug.")
    else:
        feedback.append("Fail: Workflow transition to 'On Hold' not found for Developer role.")

    # Criterion 3: Work Package Update (50 pts)
    if wp_updated:
        score += 50
        feedback.append("Success: Work package updated to 'On Hold'.")
    else:
        feedback.append("Fail: Target work package is not in 'On Hold' status.")

    # Integrity Check
    if not integrity_check:
        score = 0
        feedback.append("CRITICAL FAIL: 'New' status missing. Did you rename it instead of creating a new status?")

    # 3. Final Evaluation
    # Pass threshold: 80 points (Must at least create status and update WP, or create + configure + partial update)
    passed = score >= 80

    if details:
        feedback.append("\nDetails from system:")
        for d in details:
            feedback.append(f"- {d}")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }