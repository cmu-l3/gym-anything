#!/usr/bin/env python3
"""Verifier for Configure REST API User Sync task."""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_rest_api_user_sync(traj, env_info, task_info):
    """
    Verify Moodle REST API configuration.
    
    Scoring (100 points):
    - Web Services Enabled: 10 pts
    - REST Protocol Enabled: 10 pts
    - Service User Created: 10 pts
    - Manager Role Assigned: 15 pts
    - Service Created (Restricted & Enabled): 15 pts
    - Correct Functions Mapped: 15 pts
    - User Authorized: 10 pts
    - Token Generated: 15 pts
    
    Pass threshold: 75 points (Must have critical path: Service, User, Token)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Read Result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_rest_api_user_sync_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file missing or invalid: {e}"}

    score = 0
    feedback = []
    
    # 1. Global WS Enable (10)
    if result.get('ws_enabled') == 1:
        score += 10
        feedback.append("Web services enabled")
    else:
        feedback.append("Web services NOT enabled")
        
    # 2. REST Protocol (10)
    if result.get('rest_enabled') == 1:
        score += 10
        feedback.append("REST protocol enabled")
    else:
        feedback.append("REST protocol NOT enabled")
        
    # 3. User Created (10)
    if result.get('user_found'):
        score += 10
        feedback.append("Service user found")
    else:
        feedback.append("Service user 'sis_integration' NOT found")
        
    # 4. Manager Role (15)
    if result.get('is_manager'):
        score += 15
        feedback.append("Manager role assigned")
    else:
        feedback.append("Service user does NOT have System Manager role")
        
    # 5. Service Definition (15)
    service_ok = False
    if result.get('service_found'):
        if result.get('service_enabled') == 1 and result.get('service_restricted') == 1:
            score += 15
            service_ok = True
            feedback.append("Service created correctly (Enabled & Restricted)")
        else:
            score += 5 # Partial credit for existence
            feedback.append("Service exists but settings incorrect (Check Enabled/Restricted)")
    else:
        feedback.append("Service 'SIS User Sync' NOT found")
        
    # 6. Functions (15)
    # Require at least the 3 requested functions
    mapped_funcs = set(result.get('functions', []))
    required = {'core_user_create_users', 'core_user_update_users', 'core_user_get_users'}
    if required.issubset(mapped_funcs):
        score += 15
        feedback.append("All required API functions mapped")
    elif len(mapped_funcs.intersection(required)) > 0:
        score += 5
        feedback.append(f"Some functions missing. Found: {len(mapped_funcs.intersection(required))}/3")
    else:
        feedback.append("No required API functions mapped to service")
        
    # 7. User Authorized (10)
    if result.get('is_authorized'):
        score += 10
        feedback.append("User authorized for service")
    else:
        feedback.append("User NOT authorized for service")
        
    # 8. Token Generated (15)
    if result.get('token_exists'):
        score += 15
        feedback.append("Access token generated")
    else:
        feedback.append("No token found for user/service")

    # VLM Sanity Check (Trajectory)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        # Check if they visited the API settings pages
        vlm_res = query_vlm(
            images=frames,
            prompt="Does the user navigate through Moodle Site Administration menus to 'Server', 'Web services', or 'External services'?"
        )
        if not vlm_res.get('success') or not vlm_res.get('parsed', {}).get('answer', False):
            # We don't deduct points usually unless purely VLM task, but we note it
            pass

    # Pass Threshold
    passed = score >= 75 and result.get('service_found') and result.get('user_found') and result.get('token_exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }