#!/usr/bin/env python3
"""
Verifier for manage_customer_accounts task.

Scoring (100 points):
1. Mike Wilson blocked (status=0): 15 pts
2. Jane Smith email updated: 20 pts
3. Sarah Johnson created: 20 pts
4. Sarah Johnson email correct: 10 pts
5. Sarah Johnson active (status=1): 10 pts
6. Sarah Johnson billing profile with Chicago address: 25 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_manage_customer_accounts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_update_email = metadata.get('target_update_email', 'jane.updated@example.com')
    expected_create_email = metadata.get('target_create_email', 'sarah.johnson@example.com')
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Verify Mike Wilson blocked (15 pts)
    mike = result.get('mikewilson', {})
    if str(mike.get('status')) == '0':
        score += 15
        feedback_parts.append("Mike Wilson blocked")
    elif str(mike.get('status')) == '1':
        feedback_parts.append("Mike Wilson is still active")
    else:
        feedback_parts.append("Mike Wilson account not found")

    # 2. Verify Jane Smith email (20 pts)
    jane = result.get('janesmith', {})
    actual_jane_mail = jane.get('mail', '').strip().lower()
    if actual_jane_mail == expected_update_email.lower():
        score += 20
        feedback_parts.append("Jane Smith email updated")
    else:
        feedback_parts.append(f"Jane Smith email incorrect: got '{actual_jane_mail}'")

    # 3. Verify Sarah Johnson created (20 pts)
    sarah = result.get('sarahjohnson', {})
    if sarah.get('found'):
        score += 20
        feedback_parts.append("Sarah Johnson account created")
        
        # 4. Verify Sarah email (10 pts)
        if sarah.get('mail', '').strip().lower() == expected_create_email.lower():
            score += 10
            feedback_parts.append("Sarah email correct")
        else:
            feedback_parts.append(f"Sarah email incorrect: got '{sarah.get('mail')}'")

        # 5. Verify Sarah active (10 pts)
        if str(sarah.get('status')) == '1':
            score += 10
            feedback_parts.append("Sarah account active")
        else:
            feedback_parts.append("Sarah account is blocked/inactive")

        # 6. Verify Billing Profile (25 pts)
        if sarah.get('profile_found'):
            city = sarah.get('address_city', '')
            state = sarah.get('address_state', '')
            if 'Chicago' in city and ('IL' in state or 'Illinois' in state):
                score += 25
                feedback_parts.append("Billing profile correct (Chicago, IL)")
            else:
                score += 10 # Partial credit for creating profile but wrong address
                feedback_parts.append(f"Billing profile address mismatch: {city}, {state}")
        else:
            feedback_parts.append("No billing profile found for Sarah")

    else:
        feedback_parts.append("Sarah Johnson account NOT found")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }