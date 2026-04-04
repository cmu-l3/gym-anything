#!/usr/bin/env python3
"""
Verifier for add_admin_flight_count task.

Verifies:
1. admin.py was modified after task start.
2. admin.py contains code that counts flight plans (static analysis).
3. admin.py defines the correct column label "Plan Count".
4. The Aerobridge server is running.
5. The Admin HTML actually displays the column (dynamic check).
"""

import json
import base64
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_admin_flight_count(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    feedback = []

    # 1. Check if file was modified (Anti-gaming: Do Nothing check)
    task_start = result.get('task_start', 0)
    file_mtime = result.get('file_mtime', 0)
    
    if file_mtime > task_start:
        score += 10
        feedback.append("File admin.py was modified.")
    else:
        feedback.append("File admin.py was NOT modified.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 2. Static Code Analysis
    content_b64 = result.get('file_content_b64', '')
    try:
        content = base64.b64decode(content_b64).decode('utf-8')
    except:
        content = ""

    # Check for logic: Look for a method that takes (self, obj) or similar and calls .count()
    # Pattern: def name(self, obj): return obj.related.count()
    # We look for '.count()' and 'def '
    if '.count()' in content or 'len(' in content:
        score += 20
        feedback.append("Code Logic: Found .count() or len() calculation in admin.py.")
    else:
        feedback.append("Code Logic: Did not find obvious counting logic (.count() or len()).")

    # Check for 'list_display'
    if 'list_display' in content:
        score += 10
        feedback.append("Configuration: Found 'list_display' configuration.")
    else:
        feedback.append("Configuration: Did not find 'list_display'.")

    # Check for Label "Plan Count"
    # Ideally: short_description = 'Plan Count'
    if 'Plan Count' in content:
        score += 20
        feedback.append("Label: Found 'Plan Count' string in code.")
    else:
        feedback.append("Label: Did not find 'Plan Count' string in code.")

    # 3. Server Status
    if result.get('server_running', False):
        score += 20
        feedback.append("System: Aerobridge server is running.")
    else:
        feedback.append("System: Aerobridge server is NOT running.")

    # 4. Dynamic Verification (Did it actually work?)
    if result.get('page_has_header', False):
        score += 20
        feedback.append("Verification: 'Plan Count' column is visible in the Admin UI.")
    else:
        feedback.append("Verification: 'Plan Count' column was NOT detected in the rendered HTML.")

    # 5. VLM Trajectory Verification (Optional bonus/confirmation)
    # If dynamic check failed but code looks good, maybe we just missed the HTML parsing.
    # We won't rely on it for points here to keep it simple, as dynamic check is robust.

    total_score = score
    passed = total_score >= 80  # Requires most steps to be correct

    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback)
    }