#!/usr/bin/env python3
"""
Verifier for create_activity_type task.

Checks if the 'Product Demo' activity type was correctly created in Odoo
with the specified configuration (Name, Summary, Note, Delay, Model).
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_activity_type(traj, env_info, task_info):
    """
    Verify that the agent created the activity type correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('target_name', 'Product Demo')
    expected_summary = metadata.get('expected_summary', 'Scheduled product demonstration')
    expected_note_fragment = metadata.get('expected_note_fragment', 'prepare the demo environment')
    expected_delay = metadata.get('expected_delay', 3)
    expected_model = metadata.get('expected_model', 'crm.lead')

    # Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Begin Scoring
    score = 0
    feedback_parts = []
    
    # 1. Check existence (Critial)
    if not result.get("record_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Activity Type '{expected_name}' was not found."
        }
    
    score += 25
    feedback_parts.append(f"Activity Type '{expected_name}' created")

    # 2. Check timing (Anti-gaming)
    if result.get("is_new"):
        score += 5
    else:
        feedback_parts.append("Warning: Record timestamp verification failed")

    fields = result.get("fields", {})

    # 3. Check Summary (20 pts)
    actual_summary = fields.get("summary") or ""
    if actual_summary.strip() == expected_summary:
        score += 20
        feedback_parts.append("Summary matches")
    else:
        feedback_parts.append(f"Summary mismatch (expected '{expected_summary}', got '{actual_summary}')")

    # 4. Check Note (10 pts) - loose containment check for HTML fields
    actual_note = fields.get("default_note") or ""
    # Odoo html fields might wrap in <p>, so we check containment
    if expected_note_fragment in actual_note:
        score += 10
        feedback_parts.append("Default note contains required text")
    else:
        feedback_parts.append("Default note missing required instructions")

    # 5. Check Planned Delay (15 pts)
    actual_delay = fields.get("delay_count")
    if actual_delay == expected_delay:
        score += 15
        feedback_parts.append(f"Delay is {expected_delay} days")
    else:
        feedback_parts.append(f"Delay mismatch (expected {expected_delay}, got {actual_delay})")

    # 6. Check Model Constraint (25 pts)
    actual_model = fields.get("model_technical_name")
    if actual_model == expected_model:
        score += 25
        feedback_parts.append("Linked to correct model (crm.lead)")
    else:
        feedback_parts.append(f"Model mismatch (expected '{expected_model}', got '{actual_model}')")

    # Calculate final status
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }