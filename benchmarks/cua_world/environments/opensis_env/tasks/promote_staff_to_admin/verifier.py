#!/usr/bin/env python3
"""
Verifier for promote_staff_to_admin task.

Verifies that Sarah Jenkins (staff_id 9001) was successfully promoted 
from Teacher (profile_id 2) to Administrator (profile_id 1).
"""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_promote_staff_to_admin(traj, env_info, task_info):
    """
    Verify the staff promotion task.
    
    Scoring Criteria:
    - 40 pts: Login Authentication Profile ID updated to 1 (Admin)
    - 30 pts: OpenSIS Profile string updated to 'admin'
    - 20 pts: Navigation/Search verified (inferred from DB change or checked via VLM)
    - 10 pts: User successfully logged in (implicit if changes made)
    
    Total: 100
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract values
    initial_id = result.get('initial_profile_id', 0)
    current_id = result.get('current_profile_id', 0)
    opensis_profile = result.get('current_opensis_profile', '').lower()
    staff_profile = result.get('current_staff_profile', '').lower()
    
    score = 0
    feedback = []
    
    # 1. Verify Profile ID Change (The Core Requirement)
    # 1 = Admin, 2 = Teacher. We want 1.
    if current_id == 1:
        score += 40
        feedback.append("Success: User profile ID updated to Administrator (1).")
    elif current_id == initial_id:
        feedback.append("Fail: User profile ID unchanged.")
    else:
        feedback.append(f"Fail: User profile ID changed to unexpected value {current_id}.")

    # 2. Verify OpenSIS Profile String
    # Should be 'admin'
    if opensis_profile == 'admin':
        score += 30
        feedback.append("Success: Staff access profile set to 'admin'.")
    elif opensis_profile == 'teacher':
        feedback.append("Fail: Staff access profile still 'teacher'.")
    else:
        feedback.append(f"Fail: Staff access profile is '{opensis_profile}'.")
        
    # 3. Verify Staff Title/Profile (Supplementary)
    if 'admin' in staff_profile or 'administrator' in staff_profile:
        # We award these points if the primary ID change was successful, 
        # as a proxy for correct form interaction/navigation
        score += 20
        feedback.append("Success: Staff record title indicates administrator.")
    else:
        feedback.append(f"Note: Staff record title is '{staff_profile}'.")

    # 4. Implicit Points for Workflow Completion
    # If they managed to change the ID, they must have logged in and found the user.
    if current_id == 1:
        score += 10
        feedback.append("Success: Workflow completed.")
    
    # Anti-gaming / Sanity check
    # Ensure it wasn't already admin at start (setup ensures this, but good to check)
    if initial_id == 1:
        score = 0
        feedback = ["Error: User was already Admin at start. Setup failed."]
        
    passed = (score >= 70) # Requires at least ID change + one other field correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }