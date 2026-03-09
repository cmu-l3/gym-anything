#!/usr/bin/env python3
"""Verifier for remediate_readonly_volume_access task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remediate_readonly_volume_access(traj, env_info, task_info):
    """
    Verify that the agent diagnosed the read-only issue and restored write access.
    
    Scoring:
    - Diagnosis Log Created: 10 pts
    - Diagnosis Accuracy: 10 pts (contains 'read-only' or 'ro' or 'permission')
    - Volume Remounted: 20 pts
    - Read-Write Enabled: 30 pts
    - Write Verification: 30 pts (file created inside volume)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Diagnosis (20 pts)
    diag_exists = result.get('diagnosis_exists', False)
    diag_content = result.get('diagnosis_content', '').lower()
    
    if diag_exists:
        score += 10
        feedback_parts.append("Diagnosis log created")
        
        keywords = ['read-only', 'read only', 'readonly', 'ro ', 'permission', 'access denied', 'write protected']
        if any(k in diag_content for k in keywords):
            score += 10
            feedback_parts.append("Diagnosis accurately identified issue")
        else:
            feedback_parts.append("Diagnosis log content unclear")
    else:
        feedback_parts.append("No diagnosis log found")

    # 2. Check Mount State (20 pts)
    if result.get('is_mounted', False):
        score += 20
        feedback_parts.append("Volume is mounted")
    else:
        feedback_parts.append("Volume is NOT mounted")

    # 3. Check Read-Write Status (30 pts)
    if result.get('is_read_write', False):
        score += 30
        feedback_parts.append("Read-Write access enabled")
    else:
        if result.get('is_mounted', False):
            feedback_parts.append("Volume is still Read-Only")
    
    # 4. Check Write Verification (30 pts)
    file_created = result.get('validation_file_exists', False)
    content_correct = result.get('validation_content_correct', False)
    
    if file_created and content_correct:
        score += 30
        feedback_parts.append("Validation file created successfully")
    elif file_created:
        score += 15
        feedback_parts.append("Validation file created but content mismatch")
    else:
        feedback_parts.append("Failed to create validation file inside volume")

    # Anti-gaming check: Ensure sample data wasn't deleted (optional but good)
    if not result.get('sample_data_intact', False) and result.get('is_mounted', False):
        feedback_parts.append("WARNING: Original data missing from volume")
        # Could penalize here, but focusing on access restoration for now

    passed = score >= 80
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }