#!/usr/bin/env python3
"""
Verifier for create_student_profile task.

Scoring Criteria:
1. User with first name 'Alex' exists in DB (30 pts)
2. Last name is 'Miller' (20 pts)
3. Birth year is 2018 (10 pts)
4. User count increased or DB modified during task (10 pts)
5. VLM Verification: Agent navigated to Admin/Settings and entered data (30 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_student_profile(traj, env_info, task_info):
    """
    Verify that the student profile 'Alex Miller' (2018) was created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. READ PROGRAMMATIC RESULT FROM CONTAINER
    # ================================================================
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
    
    # ================================================================
    # 2. EVALUATE DATABASE STATE (70 pts max)
    # ================================================================
    
    # Criterion 1: User 'Alex' exists (30 pts)
    if result.get('user_found', False):
        score += 30
        feedback_parts.append("User 'Alex' found in database")
    else:
        feedback_parts.append("User 'Alex' NOT found in database")

    # Criterion 2: Last Name 'Miller' correct (20 pts)
    if result.get('last_name_match', False):
        score += 20
        feedback_parts.append("Last name 'Miller' matches")
    elif result.get('user_found', False):
        feedback_parts.append("Last name incorrect")

    # Criterion 3: Birth Year 2018 correct (10 pts)
    if result.get('birth_year_match', False):
        score += 10
        feedback_parts.append("Birth year 2018 matches")
    elif result.get('user_found', False):
        feedback_parts.append("Birth year incorrect")

    # Criterion 4: Evidence of work (DB modified or count increased) (10 pts)
    # This prevents pre-baked DBs if we were reusing containers, 
    # but primarily checks if the agent actually saved the change.
    initial_count = int(result.get('initial_user_count', 0))
    final_count = int(result.get('final_user_count', 0))
    db_modified = result.get('db_modified', False)
    
    if final_count > initial_count or db_modified:
        score += 10
        feedback_parts.append("Database updated successfully")
    else:
        feedback_parts.append("No database changes detected")

    # ================================================================
    # 3. VLM VERIFICATION (30 pts max)
    # ================================================================
    # We check if the agent actually used the UI to do this
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    prompt = """
    You are verifying if an agent successfully created a new student profile in GCompris.
    
    Look for these steps in the screenshots:
    1. Navigation to the Settings/Administration menu (often a gear icon or hamburger menu).
    2. Accessing a "Users" or "Groups" section.
    3. Filling out a form with "Alex" (First Name), "Miller" (Last Name), and "2018" (Date).
    4. Saving the profile or seeing "Alex" in a list of users.
    
    Did the agent perform the task of creating a user profile via the UI?
    """
    
    vlm_score = 0
    try:
        vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            # We assume a standard simple boolean response or confidence from the VLM helper 
            # If the helper returns a 'yes' or positive sentiment
            if "yes" in vlm_result.get("text", "").lower() or parsed.get("workflow_completed", False):
                vlm_score = 30
                feedback_parts.append("UI workflow verified by VLM")
            else:
                # Partial credit if some steps seen
                vlm_score = 15
                feedback_parts.append("Partial UI workflow observed")
        else:
            # Fallback if VLM fails but DB is correct
            if score >= 60:
                vlm_score = 30
                feedback_parts.append("VLM unavailable, trusting DB evidence")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Graceful fallback
        if score >= 60:
            vlm_score = 30
    
    score += vlm_score

    # ================================================================
    # FINAL SCORE AND RESULT
    # ================================================================
    
    # Must have at least created the user with first name to pass
    passed = (result.get('user_found', False) and score >= 70)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }