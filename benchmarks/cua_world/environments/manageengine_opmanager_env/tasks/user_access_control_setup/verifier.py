#!/usr/bin/env python3
"""
verifier.py — User Access Control Setup

Scoring (100 pts total, pass threshold 60):
  User 1 (helpdesk-tier1): 34 pts total (18 for username, 8 for email, 8 for role)
  User 2 (neteng-sarah): 34 pts total (18 for username, 8 for email, 8 for role)
  User 3 (auditor-compliance): 32 pts total (18 for username, 7 for email, 7 for role)

Anti-gaming:
  - If current_user_count <= initial_user_count, scores 0 (no new users created).
"""

import json
import os
import re

RESULT_FILE = "/tmp/user_access_result.json"

def _find_in_consolidated(db_raw, username, email, role_keyword):
    """
    Search specifically in the 'CONSOLIDATED USER QUERY' section of the DB dump.
    Returns (username_found, email_found, role_found).
    """
    u_found, e_found, r_found = False, False, False
    
    # Extract the consolidated block
    consolidated_block = ""
    if "=== CONSOLIDATED USER QUERY ===" in db_raw:
        consolidated_block = db_raw.split("=== CONSOLIDATED USER QUERY ===")[1].split("=== RAW TABLE DUMPS ===")[0]
        
    for line in consolidated_block.split('\n'):
        line_lower = line.lower()
        if username.lower() in line_lower:
            u_found = True
            if email.lower() in line_lower:
                e_found = True
            if role_keyword.lower() in line_lower or (role_keyword == 'read' and 'viewer' in line_lower):
                r_found = True
    
    return u_found, e_found, r_found

def _find_in_global(combined_text, username, email, role_keyword):
    """
    Fallback global search if consolidated query failed.
    """
    u_found = username.lower() in combined_text
    e_found = email.lower() in combined_text
    # We don't blindly grant role points on global search to avoid false positives,
    # but we can check if the keyword exists near the username.
    r_found = False
    if u_found:
        idx = combined_text.find(username.lower())
        window = combined_text[max(0, idx-500):min(len(combined_text), idx+500)]
        if role_keyword.lower() in window or (role_keyword == 'read' and ('viewer' in window or 'readonly' in window)):
            r_found = True
            
    return u_found, e_found, r_found


def verify_user_access_control_setup(traj, env_info, task_info):
    result_file = task_info.get('metadata', {}).get('result_file', RESULT_FILE)
    local_path = '/tmp/user_access_verify_result.json'

    # Retrieve the result file from the environment
    try:
        env_info['copy_from_env'](result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}. Check that export_result.sh ran."
        }

    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result file: {e}"}

    # Anti-gaming: Check if any new users were created
    try:
        initial_count = int(data.get("initial_user_count", "0"))
        current_count = int(data.get("current_user_count", "0"))
    except ValueError:
        initial_count, current_count = 0, 0

    if current_count <= initial_count and initial_count > 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"FAIL: User count did not increase (Initial: {initial_count}, Current: {current_count}). No new users created."
        }

    db_raw = data.get("db_users_raw", "")
    api_users = data.get("api_users", {})
    
    combined_text = (db_raw + " " + json.dumps(api_users)).lower()
    
    users = task_info.get("metadata", {}).get("users", [
        {"username": "helpdesk-tier1", "email": "j.mitchell@company.internal", "role_keyword": "operator"},
        {"username": "neteng-sarah", "email": "s.chen@company.internal", "role_keyword": "operator"},
        {"username": "auditor-compliance", "email": "d.park@company.internal", "role_keyword": "read"}
    ])

    score = 0
    details = []
    
    # Sub-scores per user definition (User 1, User 2, User 3)
    point_allocations = [
        {"u": 18, "e": 8, "r": 8},  # 34
        {"u": 18, "e": 8, "r": 8},  # 34
        {"u": 18, "e": 7, "r": 7}   # 32
    ]

    for idx, user_info in enumerate(users):
        username = user_info["username"]
        email = user_info["email"]
        role_keyword = user_info["role_keyword"]
        alloc = point_allocations[idx]
        
        # 1. Try consolidated DB search first (most accurate)
        u_found, e_found, r_found = _find_in_consolidated(db_raw, username, email, role_keyword)
        
        # 2. Fallback to global JSON/Text search
        if not u_found:
            u_found, e_fallback, r_fallback = _find_in_global(combined_text, username, email, role_keyword)
            e_found = e_found or e_fallback
            r_found = r_found or r_fallback
            
        # Tally points
        user_pts = 0
        if u_found:
            user_pts += alloc["u"]
            score += alloc["u"]
            details.append(f"PASS: Username '{username}' found (+{alloc['u']})")
            
            if e_found:
                user_pts += alloc["e"]
                score += alloc["e"]
                details.append(f"PASS: Email '{email}' for '{username}' found (+{alloc['e']})")
            else:
                details.append(f"FAIL: Email '{email}' for '{username}' not found (0/{alloc['e']})")
                
            if r_found:
                user_pts += alloc["r"]
                score += alloc["r"]
                details.append(f"PASS: Role mapping '{role_keyword}' for '{username}' found (+{alloc['r']})")
            else:
                details.append(f"FAIL: Role mapping '{role_keyword}' for '{username}' not found (0/{alloc['r']})")
        else:
            details.append(f"FAIL: Username '{username}' not found in system (0/{alloc['u'] + alloc['e'] + alloc['r']})")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }