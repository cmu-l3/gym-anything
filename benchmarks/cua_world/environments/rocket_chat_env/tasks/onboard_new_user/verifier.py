#!/usr/bin/env python3
"""Verifier for onboard_new_user task."""

import os
import json
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_onboard_new_user(traj, env_info, task_info):
    """
    Verify that the new user was created with correct details and added to the channel.
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('target_name', 'Maya Chen')
    expected_email = metadata.get('target_email', 'maya.chen@rocketchat.local')
    
    score = 0
    feedback_parts = []
    
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
            
    # 1. User existence (20 pts)
    user_exists = result.get('user_exists', False)
    if user_exists:
        score += 20
        feedback_parts.append("User maya.chen exists")
        
        # Anti-gaming: Check if created during task
        created_at_str = result.get('user_created_at', '')
        task_start = result.get('task_start_time', 0)
        try:
            if created_at_str:
                # Parse ISO date string properly
                created_at_str = created_at_str.replace('Z', '+00:00')
                created_dt = datetime.fromisoformat(created_at_str)
                if created_dt.timestamp() < task_start:
                    return {"passed": False, "score": 0, "feedback": "Anti-gaming failure: User was created before task started"}
        except Exception as e:
            logger.warning(f"Timestamp parsing error: {e}")
            
        # 2. Display name (15 pts)
        user_name = result.get('user_name', '')
        if user_name == expected_name:
            score += 15
            feedback_parts.append(f"Name correct ({expected_name})")
        else:
            feedback_parts.append(f"Name incorrect: '{user_name}'")
            
        # 3. Email (15 pts)
        user_email = result.get('user_email', '')
        if user_email == expected_email:
            score += 15
            feedback_parts.append(f"Email correct ({expected_email})")
        else:
            feedback_parts.append(f"Email incorrect: '{user_email}'")
            
        # 4. Role (10 pts)
        user_roles = result.get('user_roles', [])
        if "admin" not in user_roles:
            score += 10
            feedback_parts.append("Role is not admin")
        else:
            feedback_parts.append("User has admin role (incorrect)")
            
    else:
        feedback_parts.append("User maya.chen NOT found")
        
    # 5. Channel membership (40 pts)
    is_channel_member = result.get('is_channel_member', False)
    if is_channel_member:
        score += 40
        feedback_parts.append("User is in #release-updates")
    else:
        feedback_parts.append("User is NOT in #release-updates")
        
    # Add VLM verification using trajectory frames
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if frames and final:
            vlm_res = query_vlm(
                images=frames + [final], 
                prompt="Review these screenshots of an agent using Rocket.Chat. Did the agent navigate to the administration panel to create a user and interact with the channels? Answer 'yes' or 'no'."
            )
            if vlm_res and hasattr(vlm_res, 'get'):
                vlm_text = vlm_res.get('parsed', {}).get('response', str(vlm_res))
            else:
                vlm_text = str(vlm_res)
                
            if 'yes' in vlm_text.lower():
                feedback_parts.append("VLM confirms UI interaction")
    except Exception as e:
        logger.info(f"VLM verification skipped or failed: {e}")
        
    passed = (score >= 75) and user_exists and is_channel_member
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }