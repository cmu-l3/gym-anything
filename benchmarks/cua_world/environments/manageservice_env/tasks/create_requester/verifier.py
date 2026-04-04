#!/usr/bin/env python3
"""
Verifier for create_requester task (ManageEngine ServiceDesk Plus).
"""

import json
import os
import tempfile
import time
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_create_requester(traj, env_info, task_info):
    """
    Verifies if the agent created the requester 'Margaret Chen' with correct details.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy unavailable"}

    # 1. Load result data exported from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback = []
    
    # 2. Database Verification Criteria
    
    # Criterion 1: Requester Exists (15 pts)
    # The SQL query in export_result filters by unique email, so existence implies email match.
    user_found = result.get('user_found', False)
    user_data = result.get('user_data', {})
    
    if user_found:
        score += 15
        feedback.append("Requester record found.")
    else:
        feedback.append("Requester with email 'margaret.chen@pinnacletech.com' NOT found.")
        # If user not found, we check if count increased to give partial credit for *attempting* 
        # but messing up the email, though strictly the task failed primary goal.
        # We stop scoring data fields if user doesn't exist.
        return _finalize(score, feedback, traj)

    # Criterion 2: Name Verification (15 pts)
    actual_fname = user_data.get('first_name', '').strip()
    actual_lname = user_data.get('last_name', '').strip()
    expected_fname = metadata.get('expected_firstname', 'Margaret')
    expected_lname = metadata.get('expected_lastname', 'Chen')
    
    if actual_fname.lower() == expected_fname.lower() and actual_lname.lower() == expected_lname.lower():
        score += 15
        feedback.append("First and Last Name match.")
    else:
        feedback.append(f"Name mismatch: Expected '{expected_fname} {expected_lname}', found '{actual_fname} {actual_lname}'.")

    # Criterion 3: Contact Info (15 pts)
    # 10 for Phone, 5 for Mobile
    actual_phone = user_data.get('phone', '').strip()
    actual_mobile = user_data.get('mobile', '').strip()
    expected_phone = metadata.get('expected_phone', '555-0147')
    expected_mobile = metadata.get('expected_mobile', '555-0284')
    
    if actual_phone == expected_phone:
        score += 10
        feedback.append("Phone number matches.")
    else:
        feedback.append(f"Phone mismatch: Found '{actual_phone}'.")
        
    if actual_mobile == expected_mobile:
        score += 5
        feedback.append("Mobile number matches.")
    else:
        feedback.append(f"Mobile mismatch: Found '{actual_mobile}'.")

    # Criterion 4: Department (15 pts)
    actual_dept = user_data.get('department', '').strip()
    expected_dept = metadata.get('expected_department', 'Human Resources')
    
    if actual_dept.lower() == expected_dept.lower():
        score += 15
        feedback.append("Department association correct.")
    else:
        feedback.append(f"Department mismatch: Expected '{expected_dept}', found '{actual_dept}'.")

    # Criterion 5: Job Title (10 pts)
    actual_title = user_data.get('job_title', '').strip()
    expected_title = metadata.get('expected_jobtitle', 'HR Business Partner')
    
    if actual_title.lower() == expected_title.lower():
        score += 10
        feedback.append("Job Title matches.")
    else:
        feedback.append(f"Job Title mismatch: Found '{actual_title}'.")

    # Criterion 6: Employee ID (5 pts)
    actual_eid = user_data.get('employee_id', '').strip()
    expected_eid = metadata.get('expected_employee_id', 'EMP-20251087')
    
    if actual_eid == expected_eid:
        score += 5
        feedback.append("Employee ID matches.")
    else:
        feedback.append(f"Employee ID mismatch: Found '{actual_eid}'.")

    # Criterion 7: Created during task window (5 pts)
    # SDP stores CREATEDTIME in millis
    created_time = int(user_data.get('created_time', 0))
    task_start = int(result.get('task_start_timestamp', 0)) * 1000 # Convert to millis
    
    if created_time > task_start:
        score += 5
        feedback.append("Record created during task session.")
    else:
        feedback.append("Record timestamp predates task start (Anti-gaming check failed).")

    # Criterion 8: VLM Trajectory Verification (20 pts)
    # Did the agent actually use the UI?
    vlm_score = verify_trajectory(traj)
    score += vlm_score
    if vlm_score > 10:
        feedback.append("VLM confirms UI workflow.")
    else:
        feedback.append("VLM could not confirm UI workflow.")

    return _finalize(score, feedback, traj)

def verify_trajectory(traj):
    """
    Uses VLM to verify the agent navigated the UI correctly.
    """
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        return 0
        
    prompt = """
    Analyze these screenshots of an agent using ManageEngine ServiceDesk Plus.
    The goal was to create a new requester/user.
    
    Look for:
    1. Navigation to Admin or Request/User management tabs.
    2. A "New Requester" or "Add New User" form being filled out.
    3. Fields like Name, Email, Department being entered.
    
    Did the agent perform these steps? Answer yes/no and explain briefly.
    """
    
    try:
        response = query_vlm(images=frames, prompt=prompt)
        parsed = response.get('parsed', {})
        # Simple heuristic: if VLM says yes/positive, award points
        content = response.get('text', '').lower()
        if 'yes' in content and 'form' in content:
            return 20
        return 5 # Participation points if screenshots exist
    except:
        return 0

def _finalize(score, feedback, traj):
    final_score = min(100, max(0, score))
    passed = final_score >= 60
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " ".join(feedback)
    }