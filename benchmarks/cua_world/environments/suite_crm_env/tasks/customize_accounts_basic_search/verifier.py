#!/usr/bin/env python3
"""
Verifier for customize_accounts_basic_search task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_accounts_basic_search(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    score = 0
    feedback = []

    file_exists = result.get('file_exists', False)
    file_mtime = result.get('file_mtime', 0)
    task_start = result.get('task_start', 0)
    searchdefs = result.get('searchdefs')

    # 1. File deployed (20 pts)
    if file_exists:
        score += 20
        feedback.append("Custom searchdefs.php exists.")
    else:
        feedback.append("Custom searchdefs.php not found. Did you Save & Deploy in Studio?")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 2. Modified after start (20 pts)
    if file_mtime > task_start:
        score += 20
        feedback.append("File created/modified during task.")
    else:
        feedback.append("File was not modified during task (anti-gaming check failed).")

    # Helper to recursively find basic_search in the nested config dict
    def find_basic_search(d):
        if not isinstance(d, dict):
            return None
        for k, v in d.items():
            if k.lower() == 'basic_search':
                return v
            res = find_basic_search(v)
            if res is not None:
                return res
        return None

    basic = find_basic_search(searchdefs) or {}
    
    # Extract keys and name attributes to be extremely robust against PHP-to-JSON quirks
    basic_keys = []
    if isinstance(basic, dict):
        basic_keys.extend([k.lower() for k in basic.keys()])
        for v in basic.values():
            if isinstance(v, dict) and 'name' in v:
                basic_keys.append(str(v['name']).lower())
    elif isinstance(basic, list):
        for item in basic:
            if isinstance(item, dict) and 'name' in item:
                basic_keys.append(str(item['name']).lower())
            elif isinstance(item, str):
                basic_keys.append(item.lower())

    has_type = 'account_type' in basic_keys
    has_industry = 'industry' in basic_keys

    # 3. Type field added (30 pts)
    if has_type:
        score += 30
        feedback.append("'Type' field found in basic_search.")
    else:
        feedback.append("'Type' field NOT found in basic_search.")

    # 4. Industry field added (30 pts)
    if has_industry:
        score += 30
        feedback.append("'Industry' field found in basic_search.")
    else:
        feedback.append("'Industry' field NOT found in basic_search.")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }