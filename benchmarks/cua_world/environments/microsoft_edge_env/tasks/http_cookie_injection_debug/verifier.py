#!/usr/bin/env python3
"""
Verifier for http_cookie_injection_debug task.

Scoring Criteria:
1. Cookie 'debug_session_id':
   - Exists in DB (name match) - 20 pts
   - Value matches '8849-alpha-test' (from file) - 10 pts
2. Cookie 'ui_variant':
   - Exists in DB (name match) - 20 pts
   - Value matches 'dark_v2' (from file) - 10 pts
   - Secure flag set (from DB) - 10 pts
   - HttpOnly flag set (from DB) - 10 pts
3. Verification File:
   - Exists and valid JSON - 10 pts
   - Created during task - 10 pts

Total: 100 points
Pass Threshold: 65 points
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_http_cookie_injection_debug(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cookies = {c['name']: c for c in metadata.get('cookies', [])}

    # Retrieve result file
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

    # Extract data
    file_check = result.get('file_check', {})
    db_records = result.get('db_check', {}).get('records', [])
    file_content = file_check.get('content', {})

    score = 0
    feedback = []

    # --- Criterion 3: File Checks (20 pts) ---
    if file_check.get('exists') and file_check.get('valid_json'):
        score += 10
        feedback.append("Verification file exists and is valid JSON.")
    else:
        feedback.append("Verification file missing or invalid.")

    if file_check.get('created_during_task'):
        score += 10
        feedback.append("Verification file created during task.")
    else:
        feedback.append("Verification file is stale or missing.")

    # Helper to find cookie in DB list
    def find_in_db(name):
        for r in db_records:
            if r.get('name') == name:
                return r
        return None

    # --- Criterion 1: debug_session_id (30 pts) ---
    target_1 = "debug_session_id"
    expected_val_1 = expected_cookies[target_1]['value']
    
    db_rec_1 = find_in_db(target_1)
    if db_rec_1:
        score += 20
        feedback.append(f"Cookie '{target_1}' found in database.")
    else:
        feedback.append(f"Cookie '{target_1}' NOT found in database.")

    # Check value from file content (since DB value is encrypted)
    # httpbin/cookies returns format: {"cookies": {"name": "value", ...}}
    # or sometimes just {"name": "value"} depending on endpoint version, usually the former.
    # The shell script dumped the whole JSON. Let's handle both structures.
    cookies_dict = file_content.get("cookies", file_content)
    
    val_1 = cookies_dict.get(target_1)
    if val_1 == expected_val_1:
        score += 10
        feedback.append(f"Cookie '{target_1}' value matches.")
    else:
        feedback.append(f"Cookie '{target_1}' value mismatch. Expected '{expected_val_1}', got '{val_1}'.")

    # --- Criterion 2: ui_variant (50 pts) ---
    target_2 = "ui_variant"
    expected_val_2 = expected_cookies[target_2]['value']
    
    db_rec_2 = find_in_db(target_2)
    if db_rec_2:
        score += 20
        feedback.append(f"Cookie '{target_2}' found in database.")
        
        # Check flags (Secure=1, HttpOnly=1)
        # SQLite stores booleans as 1/0
        is_secure = db_rec_2.get('is_secure', 0)
        is_httponly = db_rec_2.get('is_httponly', 0)
        
        if is_secure == 1:
            score += 10
            feedback.append(f"Cookie '{target_2}' is Secure.")
        else:
            feedback.append(f"Cookie '{target_2}' is NOT Secure (-10 pts).")
            
        if is_httponly == 1:
            score += 10
            feedback.append(f"Cookie '{target_2}' is HttpOnly.")
        else:
            feedback.append(f"Cookie '{target_2}' is NOT HttpOnly (-10 pts).")
            
    else:
        feedback.append(f"Cookie '{target_2}' NOT found in database.")

    val_2 = cookies_dict.get(target_2)
    if val_2 == expected_val_2:
        score += 10
        feedback.append(f"Cookie '{target_2}' value matches.")
    else:
        feedback.append(f"Cookie '{target_2}' value mismatch. Expected '{expected_val_2}', got '{val_2}'.")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }