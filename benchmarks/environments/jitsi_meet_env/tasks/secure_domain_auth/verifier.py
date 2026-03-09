#!/usr/bin/env python3
"""
Verifier for Secure Domain Auth Task.

Criteria:
1. Environment Configuration (35 pts):
   - ENABLE_AUTH=1, AUTH_TYPE=internal, ENABLE_GUESTS=1 set in .env
   - File modified during task
2. Infrastructure State (20 pts):
   - All containers running
   - Containers restarted during task
3. User Management (20 pts):
   - 'admin' user registered in Prosody
4. Verification & Reporting (25 pts):
   - VLM confirms login prompt is visible (success of auth config)
   - Report file exists
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_domain_auth(traj, env_info, task_info):
    """
    Verify Jitsi secure domain configuration via file checks, 
    docker state inspection, and VLM visual confirmation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Environment Configuration (35 pts)
    env_score = 0
    if result.get('enable_auth_set'): env_score += 15
    if result.get('auth_type_set'): env_score += 10
    if result.get('enable_guests_set'): env_score += 5
    if result.get('env_modified_during_task'): env_score += 5
    
    score += env_score
    feedback.append(f"Environment config: {env_score}/35")

    # 2. Infrastructure State (20 pts)
    infra_score = 0
    if result.get('containers_running'): infra_score += 15
    if result.get('containers_restarted'): infra_score += 5
    
    score += infra_score
    feedback.append(f"Infrastructure state: {infra_score}/20")
    if not result.get('containers_running'):
        feedback.append("CRITICAL: Containers are not running!")

    # 3. User Management (20 pts)
    user_score = 0
    if result.get('prosody_user_registered'):
        user_score += 20
    
    score += user_score
    feedback.append(f"User registration: {user_score}/20")

    # 4. Verification & Reporting (25 pts)
    # VLM Check for Login Prompt
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    vlm_passed = False
    if final_screenshot:
        prompt = """
        You are verifying a Jitsi Meet secure domain configuration.
        Look at this screenshot of the web interface.
        
        Do you see an authentication/login prompt?
        
        Look for:
        1. A dialog box asking for "User" and "Password" (or "Username").
        2. A message saying "Authentication required" or "Waiting for host".
        3. A generic Jitsi login overlay.
        
        Answer JSON: {"login_prompt_visible": boolean, "reason": "string"}
        """
        try:
            vlm_response = query_vlm(image=final_screenshot, prompt=prompt)
            if vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                if parsed.get('login_prompt_visible', False):
                    vlm_score += 15
                    vlm_passed = True
                    feedback.append("VLM confirmed login prompt visibility.")
                else:
                    feedback.append("VLM did NOT see a login prompt.")
            else:
                feedback.append("VLM analysis failed.")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            
    if result.get('report_exists'):
        vlm_score += 10
        feedback.append("Report file created.")
        
    score += vlm_score
    feedback.append(f"Verification: {vlm_score}/25")

    # Final Pass Logic
    # Must have auth enabled, containers running, user registered, and visual confirmation
    # If VLM failed but technical checks passed, we might be lenient on VLM if score is high enough
    # But usually, visual confirmation is key for 'Verify' step
    
    critical_success = (
        result.get('enable_auth_set') and 
        result.get('containers_running') and 
        result.get('prosody_user_registered')
    )
    
    passed = score >= 60 and critical_success

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }