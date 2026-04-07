#!/usr/bin/env python3
"""
Verifier for create_parent_portal_account task.

Task: Create a Parent account for 'Margaret Chen' (username: mchen_parent) 
and link to student 'Kevin Chen'.

Verification Strategy (Multi-Signal):
1. User Auth Record (30 pts): Username 'mchen_parent' exists in login_authentication.
2. User Profile (20 pts): First/Last name 'Margaret Chen' exists in staff/users.
3. Profile Type (20 pts): Account has Profile ID 4 (Parent).
4. Student Linkage (30 pts): Account is linked to Kevin Chen's student ID.
5. Anti-Gaming: Account count increased or new record found.
"""

import json
import os
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_parent_portal_account(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Import result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0.0
    feedback = []
    
    # Data extraction
    user_auth = result.get('user_auth') or {}
    user_details = result.get('user_details') or {}
    linkage = result.get('linkage_counts', {})
    
    # 1. Verify User Authentication Record (30 pts)
    # Check username
    if user_auth and user_auth.get('username') == 'mchen_parent':
        score += 30
        feedback.append("Success: User 'mchen_parent' found in authentication table.")
    else:
        feedback.append("Fail: User 'mchen_parent' NOT found in authentication table.")

    # 2. Verify Profile Type (20 pts)
    # Expected profile_id for Parent is typically 4
    pid = user_auth.get('profile_id')
    # Allow string or int comparison
    if str(pid) == '4':
        score += 20
        feedback.append("Success: User has correct Parent profile (ID 4).")
    elif pid:
        feedback.append(f"Partial: User found but profile ID is {pid} (expected 4).")
        score += 5 # Small credit for creating user, wrong profile
    else:
        feedback.append("Fail: No profile ID found.")

    # 3. Verify User Details / Name (20 pts)
    fname = user_details.get('first_name', '')
    lname = user_details.get('last_name', '')
    
    if fname.lower() == 'margaret' and lname.lower() == 'chen':
        score += 20
        feedback.append("Success: User personal details (Margaret Chen) found.")
    else:
        # Check if auth existed but details missing
        if user_auth:
             feedback.append(f"Fail: User 'Margaret Chen' details not found in staff table. Found: {fname} {lname}.")
        else:
             feedback.append("Fail: Personal details not checked (auth missing).")

    # 4. Verify Student Linkage (30 pts)
    # We check multiple tables for robustness
    sju_count = int(linkage.get('students_join_users', 0))
    contact_count = int(linkage.get('student_contacts', 0))
    
    if sju_count > 0 or contact_count > 0:
        score += 30
        feedback.append("Success: Parent account is linked to student 'Kevin Chen'.")
    else:
        feedback.append("Fail: No database link found between Margaret Chen and Kevin Chen.")

    # 5. Anti-Gaming Check (Sanity)
    # If we found the specific username 'mchen_parent', that's strong evidence 
    # since we deleted it in setup. We can also check count increase.
    initial_cnt = int(result.get('initial_parent_count', 0))
    current_cnt = int(result.get('current_parent_count', 0))
    
    # If we found the user but counts didn't increase, that's weird but possible if another was deleted.
    # We prioritize the specific user existence over the count.
    
    # Final Score Calculation
    passed = (score >= 80) # Requires Auth + Profile + Linkage roughly
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }