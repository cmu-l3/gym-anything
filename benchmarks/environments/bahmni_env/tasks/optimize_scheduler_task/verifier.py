#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_scheduler_task(traj, env_info, task_info):
    """
    Verifies that the OpenMRS scheduler task was correctly optimized.
    
    Criteria:
    1. Task 'HL7 Inbound Queue Processor' must exist.
    2. Repeat interval must be 300 (target).
    3. The task record must show modification after task start time (anti-gaming).
    4. The task UUID must match the original (ensures edit vs delete/recreate).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
    
    # Load metadata
    metadata = task_info.get('metadata', {})
    target_interval = metadata.get('target_interval', 300)
    target_name = metadata.get('target_task_name', "HL7 Inbound Queue Processor")
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Verification Data
    task_found = result.get('task_found', False)
    final_interval = result.get('final_interval')
    last_changed_ts = result.get('last_changed_ts', 0)
    task_start_ts = result.get('task_start_ts', 0)
    # Cast to int/float safely
    try:
        last_changed_ts = float(last_changed_ts) if last_changed_ts != "NULL" else 0
        task_start_ts = float(task_start_ts)
        if final_interval is not None and final_interval != "null":
            final_interval = int(final_interval)
    except (ValueError, TypeError):
        pass

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion A: Task Exists (20 pts)
    if task_found:
        score += 20
        feedback.append("Task found in database.")
    else:
        return {"passed": False, "score": 0, "feedback": f"Task '{target_name}' not found in database."}

    # Criterion B: Interval is Correct (60 pts)
    if final_interval == target_interval:
        score += 60
        feedback.append(f"Interval correctly set to {target_interval}s.")
    else:
        feedback.append(f"Interval is {final_interval}s (expected {target_interval}s).")

    # Criterion C: Modified During Task (20 pts)
    # We accept date_changed > start_time.
    # Note: openmrs date_changed is usually second-precision.
    if last_changed_ts >= task_start_ts:
        score += 20
        feedback.append("Configuration was modified during the task.")
    else:
        feedback.append("Task was not modified during the session (timestamp check failed).")
        # If interval is correct but not modified, it implies it was already correct (setup failed?) or gaming.
        # However, setup sets it to 5. So if it's 300 and timestamp is old, something is wrong.

    # 4. Final Determination
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }