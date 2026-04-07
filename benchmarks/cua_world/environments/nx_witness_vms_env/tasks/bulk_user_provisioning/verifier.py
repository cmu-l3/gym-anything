#!/usr/bin/env python3
"""
Verifier for bulk_user_provisioning task.

Requirements to verify:
1. Users from CSV exist in the system (b.wayne, d.prince, a.curry).
2. Users have correct attributes (Email, Full Name) - checking for whitespace trimming.
3. Users have correct Role IDs (mapped from Role Name in CSV).
4. Pre-existing user (c.kent) was NOT modified (Idempotency).
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_user_provisioning(traj, env_info, task_info):
    """
    Verify that users were correctly provisioned from the CSV roster.
    """
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

    # Load data from result
    actual_users = result.get('users', [])
    actual_roles = result.get('roles', [])
    script_created = result.get('script_created', False)

    # Helper to find role ID by name
    def get_role_id(name):
        # Case insensitive match for robustness, though system is usually sensitive
        name = name.strip().lower()
        for r in actual_roles:
            if r.get('name', '').lower() == name:
                return r.get('id')
        return None

    # Helper to find user by username
    def get_user(username):
        for u in actual_users:
            if u.get('name', '').lower() == username.lower():
                return u
        return None

    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # 1. Verify Created Users (b.wayne, d.prince, a.curry)
    # ----------------------------------------------------------------
    expected_new_users = [
        {
            "username": "b.wayne", 
            "role": "Shift Supervisor", 
            "email": "b.wayne@gotham.sec", 
            "fullname": "Bruce Wayne"
        },
        {
            "username": "d.prince", 
            "role": "Advanced Viewer", 
            "email": "d.prince@gotham.sec", 
            "fullname": "Diana Prince"
        },
        {
            "username": "a.curry", 
            "role": "Viewer", 
            "email": "a.curry@atlantis.net", 
            "fullname": "Arthur Curry"
        }
    ]

    users_passed = 0
    
    for expected in expected_new_users:
        u_obj = get_user(expected['username'])
        
        if not u_obj:
            feedback_parts.append(f"Missing user: {expected['username']}")
            continue
            
        # User exists
        item_score = 0
        
        # Check Role Mapping
        expected_role_id = get_role_id(expected['role'])
        actual_role_id = u_obj.get('userRoleId')
        
        # Some default roles might have different internal IDs, but we look up what is currently in the system
        # Standard Viewer often has specific ID, but we rely on the `userRoles` list from API
        if expected_role_id and actual_role_id == expected_role_id:
            item_score += 10 # Role correct
        else:
            feedback_parts.append(f"User {expected['username']} has wrong role. Expected {expected['role']} ({expected_role_id}), got {actual_role_id}")
            
        # Check Data Cleaning (Email/Name)
        # a.curry had spaces in role " Viewer ", checked above via get_role_id stripping
        # Check if email/fullname are clean
        if u_obj.get('email') == expected['email'] and u_obj.get('fullName') == expected['fullname']:
            item_score += 10 # Data Attributes correct
        else:
             feedback_parts.append(f"User {expected['username']} attributes mismatch or uncleaned whitespace.")

        # Check Enabled
        if u_obj.get('isEnabled') is True:
            item_score += 5
            
        score += item_score
        users_passed += 1

    # Max score for new users section: 3 users * 25 pts = 75 pts
    
    # ----------------------------------------------------------------
    # 2. Verify Idempotency (c.kent)
    # ----------------------------------------------------------------
    kent = get_user("c.kent")
    idempotency_passed = False
    
    if kent:
        # Original setup: Role="Live Viewer" (ending in ...3), Password="OriginalPassword1!"
        # CSV data: Role="Viewer", Password="Krypt0n88"
        
        # We can't check password directly via API (usually hashed/hidden), 
        # but we can check Role and Email (if email was different, but it's same in csv).
        # We assume Live Viewer ID ends in ...3
        
        live_viewer_id = "00000000-0000-0000-0000-100000000003"
        
        if kent.get('userRoleId') == live_viewer_id:
            score += 20
            idempotency_passed = True
            feedback_parts.append("Idempotency check passed (c.kent not modified).")
        else:
            feedback_parts.append("Idempotency check FAILED: c.kent role was modified.")
    else:
        feedback_parts.append("CRITICAL: Pre-existing user c.kent was deleted.")

    # ----------------------------------------------------------------
    # 3. Automation Bonus
    # ----------------------------------------------------------------
    if script_created:
        score += 5
        feedback_parts.append("Automation script detected (+5).")

    # ----------------------------------------------------------------
    # Final Calculation
    # ----------------------------------------------------------------
    # Total potential: 75 + 20 + 5 = 100
    
    success = score >= 70 and idempotency_passed and (users_passed == 3)

    return {
        "passed": success,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }