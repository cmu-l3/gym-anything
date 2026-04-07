#!/usr/bin/env python3
"""
Verifier for edit_user_account_settings task.

Verifies:
1. Agent modified the user's timezone to Asia/Tokyo
2. Agent modified the user's email to emily.chen@university-tokyo.ac.jp
3. Anti-gaming (Values actually changed, elapsed time >= 5s)
4. Trajectory verification (VLM) confirms UI interaction
"""

import json
import os
import tempfile
import logging

# Attempt to import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_user_account_settings(traj, env_info, task_info):
    """
    Verify that the user account settings were successfully edited.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_timezone = metadata.get('expected_timezone', 'Asia/Tokyo')
    expected_email = metadata.get('expected_email', 'emily.chen@university-tokyo.ac.jp')

    # Read exported result
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
    
    # Retrieve exported properties
    initial_tz = result.get('initial_tz', '')
    initial_email = result.get('initial_email', '')
    current_tz = result.get('current_tz', '')
    current_email = result.get('current_email', '')
    
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    elapsed = task_end - task_start

    # Check 1: Anti-gaming timing
    if elapsed < 5:
        feedback_parts.append("Task completed suspiciously fast")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check 2: Timezone (40 pts)
    if current_tz == expected_timezone:
        score += 40
        feedback_parts.append(f"Timezone correctly set to {expected_timezone}")
    elif "tokyo" in current_tz.lower():
        score += 20
        feedback_parts.append(f"Timezone partially correct ({current_tz})")
    else:
        feedback_parts.append(f"Timezone incorrect (Expected {expected_timezone}, got {current_tz})")

    # Check 3: Email (40 pts)
    if current_email == expected_email:
        score += 40
        feedback_parts.append(f"Email correctly set to {expected_email}")
    elif "university-tokyo" in current_email.lower():
        score += 20
        feedback_parts.append(f"Email partially correct ({current_email})")
    else:
        feedback_parts.append(f"Email incorrect (Expected {expected_email}, got {current_email})")

    # Check 4: Anti-gaming state change
    tz_changed = current_tz != initial_tz
    email_changed = current_email != initial_email

    if not (tz_changed or email_changed):
        feedback_parts.append("No changes detected from initial state")
        score = 0
    
    # Check 5: VLM Trajectory (20 pts)
    vlm_score = 0
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            if frames and final_img:
                images = frames + [final_img]
                prompt = (
                    "You are verifying a web automation task in Safe Exam Browser Server. "
                    "Did the agent navigate to the User Account section, select a user, and actively edit their profile (like Timezone or Email)? "
                    "Respond with JSON: {\"interacted_with_user_form\": true/false}"
                )
                vlm_result = query_vlm(images=images, prompt=prompt)
                
                if vlm_result and vlm_result.get("parsed", {}).get("interacted_with_user_form", False):
                    vlm_score = 20
                    feedback_parts.append("VLM verified user form interaction")
                else:
                    feedback_parts.append("VLM did not detect interaction with user account form")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # Give benefit of doubt if VLM fails but DB is perfect
            if current_tz == expected_timezone and current_email == expected_email:
                vlm_score = 20
    else:
        # Give pts if we can't run VLM but DB matches perfectly
        if current_tz == expected_timezone and current_email == expected_email:
            vlm_score = 20
            
    score += vlm_score

    # Determine pass/fail
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }