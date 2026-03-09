#!/usr/bin/env python3
"""
Verifier for create_scheduler_task@1 in Bahmni.
Checks if the OpenMRS Scheduler Task was created correctly and started.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_scheduler_task(traj, env_info, task_info):
    """
    Verify the scheduler task creation.
    
    Criteria:
    1. Task exists (Name matches 'Hourly Alert Sync') - 30 pts
    2. Correct Schedulable Class - 20 pts
    3. Correct Repeat Interval (3600) - 20 pts
    4. 'Start on Startup' enabled - 10 pts
    5. Task is actively 'Started' - 20 pts
    
    Anti-gaming:
    - Task creation timestamp must be > task start time.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_task_name', 'Hourly Alert Sync')
    target_class = metadata.get('target_class', 'org.openmrs.scheduler.tasks.AlertReminderTask')
    target_interval = int(metadata.get('target_interval', 3600))
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_found = result.get('task_found', False)
    details = result.get('task_details', {})
    task_start_time = result.get('task_start_time', 0)
    
    if not task_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Task '{target_name}' was NOT found in the scheduler configuration."
        }

    # Criterion 1: Task Created (30 pts)
    score += 30
    feedback_parts.append(f"Task '{target_name}' found")

    # Anti-gaming: Check creation time
    created_ts = details.get('date_created_ts', 0)
    if created_ts < task_start_time:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Anti-gaming violation: Task appears to have been created before the session started."
        }

    # Criterion 2: Correct Class (20 pts)
    actual_class = details.get('schedulable_class', '')
    if actual_class == target_class:
        score += 20
        feedback_parts.append("Correct class")
    else:
        feedback_parts.append(f"Incorrect class (expected {target_class}, got {actual_class})")

    # Criterion 3: Correct Interval (20 pts)
    # The DB might return string, convert to int
    try:
        actual_interval = int(details.get('repeat_interval', 0))
    except (ValueError, TypeError):
        actual_interval = 0
        
    if actual_interval == target_interval:
        score += 20
        feedback_parts.append(f"Correct interval ({target_interval}s)")
    else:
        feedback_parts.append(f"Incorrect interval (expected {target_interval}, got {actual_interval})")

    # Criterion 4: Start on Startup (10 pts)
    # MySQL boolean might be 1/0 or '1'/'0'
    start_on_startup = str(details.get('start_on_startup', '0'))
    if start_on_startup in ['1', 'true', 'True']:
        score += 10
        feedback_parts.append("Start on Startup enabled")
    else:
        feedback_parts.append("Start on Startup NOT enabled")

    # Criterion 5: Task Started (20 pts)
    is_started = str(details.get('started', '0'))
    if is_started in ['1', 'true', 'True']:
        score += 20
        feedback_parts.append("Task is running")
    else:
        feedback_parts.append("Task is NOT running (status: Stopped)")

    return {
        "passed": score >= 70,  # Pass if task created + class correct + running
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }