#!/usr/bin/env python3
"""
Verifier for regional_rls_policy task.

Criteria:
1. Users 'manager_eu' and 'manager_na' exist with 'RegionalManager' role.
2. FUNCTIONAL: 'manager_eu' can only see EU profiles.
3. FUNCTIONAL: 'manager_na' can only see NA profiles.
4. METADATA: 'Profiles' records have '_allowRead' populated.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_regional_rls_policy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define Nationalities
    eu_nats = set(["Italian", "German", "French", "Spanish", "Dutch", "British", "Greek"])
    na_nats = set(["American", "Canadian", "Mexican", "Brazilian"])

    # Load result
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

    # 1. Verify Users Created (20 pts)
    users = result.get('users', {}).get('result', [])
    user_names = [u.get('name') for u in users]
    
    has_eu_user = 'manager_eu' in user_names
    has_na_user = 'manager_na' in user_names
    
    if has_eu_user: score += 5
    if has_na_user: score += 5
    
    # Verify Role Assignment
    roles_correct = True
    for u in users:
        roles = u.get('roles', [])
        if 'RegionalManager' not in roles:
            roles_correct = False
    
    if has_eu_user and has_na_user and roles_correct:
        score += 10
        feedback.append("Users created and assigned RegionalManager role.")
    else:
        feedback.append(f"User/Role issues. Users found: {user_names}")

    # Calculate Ground Truth Counts
    root_counts = result.get('root_counts', {}).get('result', [])
    total_eu_profiles = sum(item['cnt'] for item in root_counts if item.get('Nationality') in eu_nats)
    total_na_profiles = sum(item['cnt'] for item in root_counts if item.get('Nationality') in na_nats)

    # 2. Verify EU Manager View (30 pts)
    eu_view_res = result.get('eu_view', {})
    eu_view_cnt_data = eu_view_res.get('count', {}).get('result', [])
    eu_visible_count = eu_view_cnt_data[0].get('cnt', 0) if eu_view_cnt_data else 0
    
    # Check sample to ensure no leakage
    eu_sample = eu_view_res.get('sample', {}).get('result', [])
    eu_leaks = [p for p in eu_sample if p.get('Nationality') not in eu_nats]

    if eu_leaks:
        feedback.append(f"Security Breach: manager_eu sees non-EU profiles: {eu_leaks}")
    elif eu_visible_count == 0:
         feedback.append("manager_eu sees 0 profiles (should see some).")
    elif eu_visible_count == total_eu_profiles:
        score += 30
        feedback.append(f"manager_eu correctly sees exactly {eu_visible_count} EU profiles.")
    else:
        # Partial credit if close (maybe missing one nationality?)
        score += 10
        feedback.append(f"manager_eu sees {eu_visible_count} profiles, expected {total_eu_profiles}.")

    # 3. Verify NA Manager View (30 pts)
    na_view_res = result.get('na_view', {})
    na_view_cnt_data = na_view_res.get('count', {}).get('result', [])
    na_visible_count = na_view_cnt_data[0].get('cnt', 0) if na_view_cnt_data else 0

    na_sample = na_view_res.get('sample', {}).get('result', [])
    na_leaks = [p for p in na_sample if p.get('Nationality') not in na_nats]

    if na_leaks:
        feedback.append(f"Security Breach: manager_na sees non-NA profiles: {na_leaks}")
    elif na_visible_count == 0:
        feedback.append("manager_na sees 0 profiles.")
    elif na_visible_count == total_na_profiles:
        score += 30
        feedback.append(f"manager_na correctly sees exactly {na_visible_count} NA profiles.")
    else:
        score += 10
        feedback.append(f"manager_na sees {na_visible_count} profiles, expected {total_na_profiles}.")

    # 4. Verify RLS Implementation Details (20 pts)
    # Check if _allowRead is actually populated on profiles
    allow_read_data = result.get('allow_read_metadata', {}).get('result', [])
    if allow_read_data and len(allow_read_data) > 0:
        score += 20
        feedback.append("RLS metadata (_allowRead) is populated on profiles.")
    else:
        feedback.append("No _allowRead data found on profiles (did you use UPDATE Profiles SET _allowRead=...?)" )

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }