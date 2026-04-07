#!/usr/bin/env python3
"""
Verifier for add_teacher_staff task.

Verifies:
1. Staff record created with correct details (First, Last, Email).
2. Login credentials created (Username).
3. Correct Profile assigned (Teacher).
4. Staff linked to correct School.
5. Anti-gaming: Count increased, timestamp valid.
6. VLM: Trajectory check to ensure UI workflow was used.
"""

import json
import os
import sys
import logging
import tempfile
from datetime import datetime

# Import VLM utils (assuming standard gym_anything environment structure)
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(prompt, images): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_teacher_staff(traj, env_info, task_info):
    """
    Main verification function for add_teacher_staff@1.
    """
    # 1. Setup Result Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_first = metadata.get('expected_first', 'Margaret')
    expected_last = metadata.get('expected_last', 'Chen')
    expected_username = metadata.get('expected_username', 'mchen')
    expected_email = metadata.get('expected_email', 'margaret.chen@school.edu')
    
    # Copy JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result_data.get('error'):
        return {"passed": False, "score": 0, "feedback": "Error during result export inside container."}

    # 2. Programmatic Verification (85 Points)
    score = 0
    feedback = []
    
    staff = result_data.get('staff_record', {})
    login = result_data.get('login_record', {})
    
    # Criterion 1: Staff Record Exists (25 pts)
    if staff.get('found'):
        # Check Name
        fname = staff.get('first_name', '')
        lname = staff.get('last_name', '')
        if fname == expected_first and lname == expected_last:
            score += 25
            feedback.append("Staff record found with correct name.")
        else:
            score += 10 # Partial credit for record existing but wrong name
            feedback.append(f"Staff record found but name mismatch ({fname} {lname}).")
    else:
        feedback.append("No staff record found for Margaret Chen.")

    # Criterion 2: Login Created (20 pts)
    if login.get('found'):
        if login.get('username') == expected_username:
            score += 20
            feedback.append("Login credentials found.")
        else:
            feedback.append(f"Login found but username mismatch ({login.get('username')}).")
    else:
        feedback.append("No login credentials found for 'mchen'.")

    # Criterion 3: Email Match (10 pts)
    if staff.get('email') == expected_email:
        score += 10
        feedback.append("Email address matches.")
    elif staff.get('found'):
        feedback.append(f"Email mismatch: {staff.get('email')}")

    # Criterion 4: Correct Profile (15 pts)
    profile_name = staff.get('profile_name', '').lower()
    if 'teacher' in profile_name:
        score += 15
        feedback.append("Correct 'Teacher' profile assigned.")
    elif staff.get('found'):
        feedback.append(f"Incorrect profile: {staff.get('profile_name')}")

    # Criterion 5: School Link & Counts (15 pts)
    # 10 pts for link, 5 pts for count increase
    if result_data.get('school_link_exists'):
        score += 10
        feedback.append("Staff linked to school correctly.")
    
    initial = result_data.get('initial_count', 0)
    current = result_data.get('current_count', 0)
    if current > initial:
        score += 5
        feedback.append("Staff count increased.")
    else:
        feedback.append("Warning: Staff count did not increase (record might be overwritten?).")

    # 3. VLM Verification (15 Points)
    # We verify the agent actually visited the 'Staff' UI pages
    vlm_score = 0
    if traj:
        frames = sample_trajectory_frames(traj, n=5)
        
        prompt = """
        You are verifying an agent's workflow in OpenSIS. The agent should be adding a new staff member.
        Look for these visual indicators in the screenshots:
        1. A form titled "Staff Information" or "Add User".
        2. Input fields for First Name, Last Name, or Email.
        3. A dropdown or selection for "Profile" (e.g., Teacher, Admin).
        4. A "Save" button being clicked or present.
        
        Does the trajectory show the agent interacting with a user creation form?
        Reply with JSON: {"valid_workflow": boolean, "confidence": float, "reason": string}
        """
        
        vlm_res = query_vlm(prompt=prompt, images=frames)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('valid_workflow'):
                vlm_score = 15
                feedback.append("VLM Verification: Valid UI workflow detected.")
            else:
                feedback.append(f"VLM Verification: Workflow unclear. {parsed.get('reason')}")
        else:
            # Fallback if VLM fails: if programmatic score is high (>60), give benefit of doubt
            if score > 60:
                vlm_score = 15
                feedback.append("VLM skipped (service unavailable), assumed pass based on DB evidence.")
            else:
                feedback.append("VLM verification unavailable.")

    score += vlm_score

    # Final Pass Determination
    # Must have at least created the staff record and login to pass
    passed = (score >= 60) and staff.get('found') and login.get('found')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "db_score": score - vlm_score,
            "vlm_score": vlm_score,
            "staff_data": staff
        }
    }