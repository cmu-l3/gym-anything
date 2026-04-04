#!/usr/bin/env python3
"""Verifier for audit_agent_performance task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_agent_performance(traj, env_info, task_info):
    """
    Verify that the agent correctly counted the closed tickets for Marcus Chen.
    
    Criteria:
    1. Output file exists (30 pts)
    2. File was created/modified during task (10 pts)
    3. The number in the file matches the database count exactly (60 pts)
    
    Pass threshold: 100 points (Accuracy is paramount in auditing)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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
    
    # Extract data
    file_exists = result.get('file_exists', False)
    file_created = result.get('file_created_during_task', False)
    user_answer_str = result.get('user_answer', '')
    actual_count = result.get('actual_count', -1)
    
    # Criterion 1: File Existence (30 pts)
    if file_exists:
        score += 30
        feedback_parts.append("Report file exists")
    else:
        feedback_parts.append("Report file NOT found at /home/ga/Documents/marcus_closed_count.txt")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: File Created During Task (10 pts)
    if file_created:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp indicates it wasn't created during this session")

    # Criterion 3: Accuracy (60 pts)
    try:
        user_val = int(user_answer_str)
        actual_val = int(actual_count)
        
        if user_val == actual_val:
            score += 60
            feedback_parts.append(f"Count matches exactly ({user_val})")
        else:
            feedback_parts.append(f"Count mismatch: Agent reported {user_val}, actual is {actual_val}")
            
    except ValueError:
        feedback_parts.append(f"Could not parse valid number from file content: '{user_answer_str}'")

    # Final Pass/Fail
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }