#!/usr/bin/env python3
"""
Verifier for create_staff_login@1
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_staff_login(traj, env_info, task_info):
    """
    Verify that the agent created a user login linked to the existing staff member.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    user_record = result.get('user_record')
    staff_records = result.get('staff_records', [])
    initial_count = result.get('initial_staff_count', 0)
    final_count = result.get('final_staff_count', 0)

    # 1. Verify User Creation (30 pts)
    # Check if 'sconnor' exists in login_authentication
    if user_record and user_record.get('username') == 'sconnor':
        score += 30
        feedback.append("User 'sconnor' created successfully.")
    else:
        feedback.append("User 'sconnor' NOT found in system.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Verify Profile (20 pts)
    # Profile ID 2 is usually Teacher
    profile_id = str(user_record.get('profile_id', ''))
    if profile_id == '2':
        score += 20
        feedback.append("User profile set to Teacher.")
    else:
        feedback.append(f"Incorrect profile ID (Expected 2/Teacher, got {profile_id}).")

    # 3. Verify Linkage (30 pts)
    # The staff record for Sarah Connor should have a linked_user_id that matches user_record['user_id']
    created_user_id = str(user_record.get('user_id'))
    
    linked = False
    target_staff = None
    
    # Find the specific staff record for Sarah Connor
    # There might be multiple if the agent messed up, we check if ANY is linked correctly
    for staff in staff_records:
        if staff.get('first_name') == 'Sarah' and staff.get('last_name') == 'Connor':
            # In bash export, JSON null becomes None in python or 'null' string depending on jq
            # We handle string/int conversion
            s_uid = str(staff.get('linked_user_id', ''))
            if s_uid == created_user_id:
                linked = True
                target_staff = staff
                break
    
    if linked:
        score += 30
        feedback.append("User correctly linked to Staff record.")
    else:
        feedback.append("User account exists but is NOT linked to the Sarah Connor staff record.")

    # 4. Verify No Duplicates (20 pts)
    # Staff count should not have increased.
    # If the agent created a NEW staff member instead of linking, count will increase.
    if final_count > initial_count:
        feedback.append("Duplicate staff record created (Count increased). Task required linking to EXISTING staff.")
    elif final_count < initial_count:
         feedback.append("Staff record deleted?") # Unlikely
    else:
        score += 20
        feedback.append("No duplicate staff records created.")

    # Pass threshold
    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }