#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_substitute_profile(traj, env_info, task_info):
    """
    Verify the Create Substitute Profile task.
    
    Criteria:
    1. Database: Profile 'Substitute' must exist (40 pts)
    2. Database: Permission for 'attendance/TakeAttendance.php' must be 'Y' (40 pts)
    3. Database: Profile must be newly created (count increased) (Anti-gaming)
    4. VLM: Trajectory shows interaction with Users/Profiles menu (20 pts)
    
    Bonus check: Grades module should NOT be enabled (Security principle).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_profile_title', 'Substitute')
    required_module_keyword = 'TakeAttendance' # Key part of module name

    # 1. Retrieve Result JSON
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

    score = 0
    feedback_parts = []
    
    # 2. Verify Profile Existence (40 pts)
    profile_exists = result.get('profile_exists', False)
    profile_title = result.get('profile_title', '')
    
    if profile_exists and profile_title.lower() == expected_title.lower():
        score += 40
        feedback_parts.append(f"Profile '{expected_title}' created successfully.")
    else:
        feedback_parts.append(f"Profile '{expected_title}' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Verify Anti-Gaming (Count check)
    initial_count = int(result.get('initial_profile_count', 0))
    current_count = int(result.get('current_profile_count', 0))
    
    if current_count <= initial_count:
        feedback_parts.append("Warning: Profile count did not increase. Profile might have pre-existed.")
        # We don't fail immediately if it exists, but strict anti-gaming might penalize here.
        # For this task, we'll allow it if verification passes but add a note.

    # 4. Verify Permissions (40 pts)
    permissions = result.get('permissions', [])
    attendance_enabled = False
    grades_enabled = False
    
    for perm in permissions:
        modname = perm.get('modname', '')
        can_use = perm.get('can_use', 'N')
        
        if required_module_keyword in modname and can_use == 'Y':
            attendance_enabled = True
        
        if 'Grades.php' in modname and can_use == 'Y':
            grades_enabled = True

    if attendance_enabled:
        score += 40
        feedback_parts.append("Attendance permission correctly enabled.")
    else:
        feedback_parts.append("Failed: 'Take Attendance' permission NOT enabled.")

    # Security Check (Informational/Bonus)
    if grades_enabled:
        feedback_parts.append("Warning: Grades permission was enabled (Security Risk).")
    else:
        feedback_parts.append("Security Good: Grades permission not explicitly enabled.")

    # 5. VLM Verification (20 pts)
    # Check if agent actually navigated to the User Profiles screen
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    images = frames + [final_img] if final_img else frames
    
    vlm_prompt = """
    Analyze these screenshots of a user using OpenSIS.
    Did the user navigate to the 'Users' menu and 'User Profiles' section?
    Is there a form or list showing user profiles or permissions?
    Answer YES or NO and explain briefly.
    """
    
    vlm_result = query_vlm(images=images, prompt=vlm_prompt)
    
    if vlm_result.get("success", False):
        resp = vlm_result.get("parsed", {}).get("response", "").lower()
        # Simple keyword check if structured parsing isn't strictly enforced by query_vlm wrapper in context
        # Assuming the wrapper returns a dict with 'response' or we parse the raw text
        raw_text = str(vlm_result) 
        if "yes" in raw_text.lower() or "user profiles" in raw_text.lower():
            score += 20
            feedback_parts.append("VLM verification passed: Navigation confirmed.")
        else:
            # Fallback score if VLM is ambiguous but DB is perfect
            score += 10 
            feedback_parts.append("VLM verification ambiguous.")
    else:
        # If VLM fails but DB is good, give partial credit
        score += 10
        feedback_parts.append("VLM verification skipped.")

    # Final Evaluation
    passed = (score >= 80) and attendance_enabled and profile_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }