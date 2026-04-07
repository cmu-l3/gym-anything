#!/usr/bin/env python3
"""
Verifier for register_fixed_asset task.

Verifies:
1. Asset record exists with correct Search Key.
2. Asset was created during the task session.
3. Fields (Name, Description, Date, Useful Life) match requirements.
4. Asset Group is assigned.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_fixed_asset(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract metadata
    metadata = task_info.get('metadata', {})
    expected_key = metadata.get('expected_search_key', "TRUCK-2024-001")
    expected_name_frag = metadata.get('expected_name_fragment', "Ford Transit")
    expected_date = metadata.get('expected_service_date', "2024-06-01")
    expected_life = metadata.get('expected_life_years', 7)

    score = 0
    feedback = []

    # 1. Record Exists (20 pts)
    if result.get('record_found', False):
        score += 20
        feedback.append(f"Asset '{expected_key}' found.")
    else:
        feedback.append(f"Asset '{expected_key}' NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Anti-Gaming: Created during task (5 pts)
    if result.get('created_during_task', False):
        score += 5
        feedback.append("Record created during task session.")
    else:
        feedback.append("Record existed prior to task (reused old record?).")

    # 3. Name Correct (15 pts)
    name = result.get('name', '')
    if expected_name_frag.lower() in name.lower():
        score += 15
        feedback.append("Name matches.")
    else:
        feedback.append(f"Name mismatch (Expected fragment '{expected_name_frag}', got '{name}').")

    # 4. Description Present (10 pts)
    desc = result.get('description', '')
    if desc and len(desc) > 5:
        score += 10
        feedback.append("Description present.")
    else:
        feedback.append("Description missing or too short.")

    # 5. Asset Group Assigned (15 pts)
    if result.get('group_id_present', False):
        score += 15
        feedback.append("Asset Group assigned.")
    else:
        feedback.append("Asset Group NOT assigned.")

    # 6. In-Service Date Correct (15 pts)
    svc_date = result.get('service_date', '')
    # Handle potential timestamp format (YYYY-MM-DD HH:MM:SS) vs Date (YYYY-MM-DD)
    if expected_date in svc_date:
        score += 15
        feedback.append(f"In-Service Date correct ({expected_date}).")
    else:
        feedback.append(f"In-Service Date incorrect (Expected {expected_date}, got {svc_date}).")

    # 7. Useful Life Years (15 pts)
    life = result.get('life_years', 0)
    try:
        if int(life) == int(expected_life):
            score += 15
            feedback.append(f"Useful Life correct ({life} years).")
        else:
            feedback.append(f"Useful Life incorrect (Expected {expected_life}, got {life}).")
    except:
        feedback.append(f"Useful Life format error (got {life}).")

    # 8. Active Record (5 pts)
    if result.get('is_active', 'N') == 'Y':
        score += 5
        feedback.append("Record is active.")
    else:
        feedback.append("Record is inactive.")

    passed = score >= 65 and result.get('record_found', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }