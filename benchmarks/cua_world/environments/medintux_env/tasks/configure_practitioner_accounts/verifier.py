#!/usr/bin/env python3
"""
Verifier for configure_practitioner_accounts task.

Verifies:
1. Database contains the two new practitioner accounts (mlefebvre, smartin).
2. Account details (Name, Specialty, IDs) are correct.
3. Passwords are MD5 hashed.
4. Report file exists and contains schema info.
"""

import json
import tempfile
import os
import logging
import re
import hashlib

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_practitioner_accounts(traj, env_info, task_info):
    """
    Verify practitioner account creation in MedinTux database.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    max_score = 100

    # Get data from result
    found_table = result.get('found_table', '')
    user_data = result.get('user_data', [])
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content_preview', '')

    # --- Criterion 1: Users exist in database (30 pts) ---
    users_found = {u.get('Login', u.get('FchGnrl_Login', u.get('ut_login', ''))): u for u in user_data}
    # Normalize keys to lowercase for easier lookup if column names vary
    users_normalized = {}
    for u in user_data:
        # Find the login value
        login = None
        for k, v in u.items():
            if 'login' in k.lower() and v in ['mlefebvre', 'smartin']:
                login = v
                break
        if login:
            # Create a dict with lowercase keys
            users_normalized[login] = {k.lower(): v for k, v in u.items()}

    mlefebvre = users_normalized.get('mlefebvre')
    smartin = users_normalized.get('smartin')

    if mlefebvre:
        score += 15
        feedback_parts.append("Physician 'mlefebvre' found in DB")
    else:
        feedback_parts.append("Physician 'mlefebvre' NOT found in DB")

    if smartin:
        score += 15
        feedback_parts.append("Nurse 'smartin' found in DB")
    else:
        feedback_parts.append("Nurse 'smartin' NOT found in DB")

    # --- Criterion 2: Physician Details (20 pts) ---
    if mlefebvre:
        # Check name fields (searching values in any column)
        vals = [str(v).lower() for v in mlefebvre.values()]
        
        if any('lefebvre' in v for v in vals) and any('marie' in v for v in vals):
            score += 10
            feedback_parts.append("Physician name correct")
        else:
            feedback_parts.append("Physician name incorrect")

        if any('10003456789' in v for v in vals): # RPPS
            score += 5
            feedback_parts.append("Physician RPPS correct")
        else:
            feedback_parts.append("Physician RPPS missing/wrong")

        if any('cardio' in v for v in vals):
            score += 5
            feedback_parts.append("Physician specialty correct")
        else:
            feedback_parts.append("Physician specialty missing/wrong")

    # --- Criterion 3: Nurse Details (20 pts) ---
    if smartin:
        vals = [str(v).lower() for v in smartin.values()]
        
        if any('martin' in v for v in vals) and any('sophie' in v for v in vals):
            score += 10
            feedback_parts.append("Nurse name correct")
        else:
            feedback_parts.append("Nurse name incorrect")
            
        if any('10009876543' in v for v in vals): # RPPS
            score += 5
            feedback_parts.append("Nurse RPPS correct")
        else:
            feedback_parts.append("Nurse RPPS missing/wrong")

        if any('infirm' in v for v in vals):
            score += 5
            feedback_parts.append("Nurse specialty correct")
        else:
            feedback_parts.append("Nurse specialty missing/wrong")

    # --- Criterion 4: Password Hashing (10 pts) ---
    # Expected MD5 hashes
    # Cardio2024! -> md5
    # Infirm2024! -> md5
    
    # We verify that the stored password looks like an MD5 hash (32 hex chars)
    # AND optionally check if it matches the expected hash
    
    def check_hash(user_dict, plain_pwd):
        # Calculate expected hash
        expected_md5 = hashlib.md5(plain_pwd.encode()).hexdigest()
        
        # Check all values in row
        for v in user_dict.values():
            if v == expected_md5:
                return True
            # Also check if it's just a 32-char hex string (generic hash check)
            # but NOT the plaintext
            if isinstance(v, str) and re.match(r'^[a-fA-F0-9]{32}$', v) and v != plain_pwd:
                # It's a hash, maybe salt was used? MedinTux usually raw MD5.
                # We'll give credit if it's a hash and not plaintext.
                return True
        return False

    if mlefebvre:
        if check_hash(mlefebvre, "Cardio2024!"):
            score += 5
            feedback_parts.append("Physician password hashed")
        else:
            feedback_parts.append("Physician password NOT hashed or incorrect")

    if smartin:
        if check_hash(smartin, "Infirm2024!"):
            score += 5
            feedback_parts.append("Nurse password hashed")
        else:
            feedback_parts.append("Nurse password NOT hashed or incorrect")

    # --- Criterion 5: Report File (20 pts) ---
    if report_exists:
        score += 5
        feedback_parts.append("Report file exists")
        
        content_lower = report_content.lower()
        
        # Check for table name
        if found_table.lower() in content_lower:
            score += 5
            feedback_parts.append("Report mentions correct table")
            
        # Check for schema info (keywords from DESCRIBE)
        if 'field' in content_lower or 'type' in content_lower or 'varchar' in content_lower:
            score += 5
            feedback_parts.append("Report contains schema info")
            
        # Check for select/count info
        if 'mlefebvre' in content_lower and 'smartin' in content_lower:
            score += 5
            feedback_parts.append("Report contains query results")
    else:
        feedback_parts.append("Report file missing")

    passed = (score >= 60) and (mlefebvre is not None) and (smartin is not None)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }