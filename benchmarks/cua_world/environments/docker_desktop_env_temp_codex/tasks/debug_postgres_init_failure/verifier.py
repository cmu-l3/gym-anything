#!/usr/bin/env python3
"""
Verifier for debug_postgres_init_failure task.

Criteria:
1. The Postgres container must be running (20 pts).
2. The 'products' table must exist in the database (40 pts).
3. The initialization script must have run AUTOMATICALLY (40 pts).
   - Checked via container logs for the postgres entrypoint message.
   - OR verified by checking if the volume was recreated during the task.
   - This prevents simply manually pasting SQL into the running container
     without fixing the underlying volume/init issue.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debug_postgres_init_failure(traj, env_info, task_info):
    """
    Verify that the stale volume was removed and the database initialized correctly.
    """
    # 1. Setup copy from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load result JSON
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

    # 3. Extract metrics
    container_running = result.get('container_running', False)
    table_exists = result.get('table_exists', False)
    init_script_ran = result.get('init_script_ran_automatically', False)
    volume_recreated = result.get('volume_recreated', False)
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Container Running (20 pts)
    if container_running:
        score += 20
        feedback_parts.append("Database container is running (+20)")
    else:
        feedback_parts.append("Database container is NOT running")
        
    # Criterion 2: Table Exists (40 pts)
    if table_exists:
        score += 40
        feedback_parts.append("Table 'products' exists (+40)")
    else:
        feedback_parts.append("Table 'products' does NOT exist")

    # Criterion 3: Init Mechanism Fixed (40 pts)
    # Valid if logs show it ran OR if volume timestamp proves recreation
    if init_script_ran or volume_recreated:
        score += 40
        feedback_parts.append("Initialization script ran automatically/Volume recreated (+40)")
    else:
        if table_exists:
            feedback_parts.append("WARNING: Table exists but initialization script did not run automatically. Did you just create the table manually? The environment is still broken for fresh starts.")
        else:
            feedback_parts.append("Initialization script did not run.")

    # Final logic
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "container_running": container_running,
            "table_exists": table_exists,
            "init_mechanism_fixed": (init_script_ran or volume_recreated)
        }
    }