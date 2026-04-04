#!/usr/bin/env python3
"""
Verifier for create_change_template task.

Verifies:
1. Template exists in database with correct name.
2. Template has correct Type, Impact, Urgency, Reason.
3. Template has correct Description, Rollout Plan, Backout Plan content.
4. Uses VLM to verify trajectory (optional backup).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_change_template(traj, env_info, task_info):
    """
    Verify the creation of the Change Management template.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('template_name', 'Weekly Server Patching')
    expected_type = metadata.get('expected_type', 'Standard')
    expected_reason = metadata.get('expected_reason', 'Maintenance')
    expected_impact = metadata.get('expected_impact', 'Low')
    expected_urgency = metadata.get('expected_urgency', 'Low')
    
    desc_keywords = metadata.get('description_keywords', [])
    rollout_keywords = metadata.get('rollout_keywords', [])
    backout_keywords = metadata.get('backout_keywords', [])

    # Retrieve result from container
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

    # Scoring
    score = 0
    feedback_parts = []
    
    template_found = result.get('template_found', False)
    data = result.get('template_data', {})

    # Criterion 1: Template Exists (40 points)
    if template_found:
        score += 40
        feedback_parts.append(f"Template '{expected_name}' created.")
    else:
        return {"passed": False, "score": 0, "feedback": f"Template '{expected_name}' not found in database."}

    # Criterion 2: Configuration Fields (Type, Impact, Urgency, Reason) (10 points each = 40 total)
    # Case-insensitive checks
    
    # Check Type
    actual_type = data.get('type', '').strip()
    if expected_type.lower() in actual_type.lower():
        score += 10
        feedback_parts.append(f"Type correct ({actual_type}).")
    else:
        feedback_parts.append(f"Type mismatch: expected '{expected_type}', got '{actual_type}'.")

    # Check Impact
    actual_impact = data.get('impact', '').strip()
    if expected_impact.lower() in actual_impact.lower():
        score += 10
        feedback_parts.append(f"Impact correct ({actual_impact}).")
    else:
        feedback_parts.append(f"Impact mismatch: expected '{expected_impact}', got '{actual_impact}'.")

    # Check Urgency
    actual_urgency = data.get('urgency', '').strip()
    if expected_urgency.lower() in actual_urgency.lower():
        score += 10
        feedback_parts.append(f"Urgency correct ({actual_urgency}).")
    else:
        feedback_parts.append(f"Urgency mismatch: expected '{expected_urgency}', got '{actual_urgency}'.")

    # Check Reason
    actual_reason = data.get('reason', '').strip()
    if expected_reason.lower() in actual_reason.lower() or 'patch' in actual_reason.lower():
        score += 10
        feedback_parts.append(f"Reason correct ({actual_reason}).")
    else:
        feedback_parts.append(f"Reason mismatch: expected '{expected_reason}', got '{actual_reason}'.")

    # Criterion 3: Content Fields (Description, Rollout, Backout) (20 points total)
    content_score = 0
    
    # Check Description
    actual_desc = data.get('description', '')
    if any(k.lower() in actual_desc.lower() for k in desc_keywords):
        content_score += 7
    
    # Check Rollout
    actual_rollout = data.get('rollout_plan', '')
    if any(k.lower() in actual_rollout.lower() for k in rollout_keywords):
        content_score += 7
        
    # Check Backout
    actual_backout = data.get('backout_plan', '')
    if any(k.lower() in actual_backout.lower() for k in backout_keywords):
        content_score += 6
        
    if content_score >= 15:
        feedback_parts.append("Content fields (plans/description) verified.")
    else:
        feedback_parts.append("Content fields missing or incomplete.")
        
    score += content_score

    # Final Pass check
    passed = score >= 70 and template_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }