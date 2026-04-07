#!/usr/bin/env python3
"""
Verifier for configure_repo_automation task.

Criteria:
1. Fixing keywords: Must include 'fixes', 'closes', 'resolves' (20 pts)
2. Applied status: Must be 'Closed' (mapped by ID) (20 pts)
3. % Done: Must be '100%' (15 pts)
4. Time logging: Must be enabled (25 pts)
5. Activity: Must be 'Development' (mapped by ID) (20 pts)
6. Anti-gaming: Settings must be updated during task execution.
"""

import json
import os
import sys
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_repo_automation(traj, env_info, task_info):
    # 1. Setup access to result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Data
    data = result.get('redmine_data', {})
    task_start = result.get('task_start', 0)
    
    actual_keywords = data.get('keywords', '') or ''
    actual_status_id = str(data.get('status_id', ''))
    actual_done_ratio = str(data.get('done_ratio', ''))
    actual_log_enabled = str(data.get('logtime_enabled', '0'))
    actual_activity_id = str(data.get('activity_id', ''))
    
    expected_status_id = str(data.get('expected_status_id', 'EXPECTED_NOT_FOUND'))
    expected_activity_id = str(data.get('expected_activity_id', 'EXPECTED_NOT_FOUND'))
    
    # Anti-gaming check (optional but recommended)
    # updated_on = data.get('settings_updated_on') # ISO string from Rails
    # Logic to parse ISO string and compare to task_start can be added here
    # For now, we rely on the specific values matching our target, as we reset them in setup.

    score = 0
    feedback = []

    # 3. Verify Keywords (20 pts)
    # Flexible check: contains all required words, comma separated
    required_kws = task_info.get('metadata', {}).get('required_keywords', ['fixes', 'closes', 'resolves'])
    normalized_actual = [k.strip().lower() for k in actual_keywords.split(',')]
    
    missing_kws = [k for k in required_kws if k not in normalized_actual]
    
    if not missing_kws:
        score += 20
    else:
        feedback.append(f"Missing keywords: {', '.join(missing_kws)}")

    # 4. Verify Applied Status (20 pts)
    if expected_status_id != 'EXPECTED_NOT_FOUND' and actual_status_id == expected_status_id:
        score += 20
    else:
        feedback.append(f"Applied status incorrect (Expected ID {expected_status_id}, got {actual_status_id})")

    # 5. Verify % Done (15 pts)
    if actual_done_ratio == '100':
        score += 15
    else:
        feedback.append(f"% Done incorrect (Expected 100, got {actual_done_ratio})")

    # 6. Verify Time Logging Enabled (25 pts)
    # Redmine stores boolean settings as "1" or "0" often, or true/false in JSON
    if actual_log_enabled in ['1', 'true', 'True']:
        score += 25
    else:
        feedback.append("Time logging was not enabled")

    # 7. Verify Activity (20 pts)
    if expected_activity_id != 'EXPECTED_NOT_FOUND' and actual_activity_id == expected_activity_id:
        score += 20
    else:
        feedback.append(f"Time logging activity incorrect (Expected ID {expected_activity_id}, got {actual_activity_id})")

    # 8. Final Result
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback) if feedback else "All settings configured correctly."
    }