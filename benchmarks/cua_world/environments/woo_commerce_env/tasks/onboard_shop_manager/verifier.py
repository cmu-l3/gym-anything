#!/usr/bin/env python3
"""
Verifier for Onboard Shop Manager task.

Verification Strategy:
1. Programmatic (80 pts):
   - User exists (20 pts)
   - Correct Role (30 pts) - MUST be shop_manager, MUST NOT be administrator
   - Correct Name (20 pts)
   - Correct Password (10 pts)
2. VLM Trajectory (20 pts):
   - Confirm navigation to Users > Add New
   - Confirm form filling
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a new user in WordPress.

The images are sampled chronologically.

For successful user creation, the agent should:
1. Navigate to Users > Add New
2. Fill in the "Add New User" form (Username, Email, First/Last Name)
3. Click "Show Password" or enter a password
4. Select a Role (specifically Shop Manager)
5. Click "Add New User"

Assess:
1. WORKFLOW_COMPLETED: Did the agent reach the user creation form and fill it?
2. ROLE_SELECTION_VISIBLE: Can you see the Role dropdown being changed?
3. SUCCESS_INDICATORS: Is there a "New user created" message or similar?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "role_selection_visible": true/false,
    "success_indicators": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_onboard_shop_manager(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_email = metadata.get('expected_email', 'morgan.lee@example.com')
    expected_username = metadata.get('expected_username', 'morgan_ops')
    expected_role = metadata.get('expected_role', 'shop_manager')
    forbidden_role = metadata.get('forbidden_role', 'administrator')
    
    score = 0
    feedback_parts = []
    
    # 1. Load Result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    user_exists = result.get('user_exists', False)
    user_data = result.get('user_data', {})
    password_valid = result.get('password_valid', 'false')

    # 2. Programmatic Verification
    if not user_exists:
        return {"passed": False, "score": 0, "feedback": "User was not created."}
    
    score += 20
    feedback_parts.append("User created")

    # Check Email & Username (Basic Sanity)
    if user_data.get('email') == expected_email:
        feedback_parts.append("Email correct")
    else:
        feedback_parts.append(f"Email mismatch: {user_data.get('email')}")

    # Check Name (20 pts split)
    if user_data.get('first_name') == metadata.get('expected_firstname'):
        score += 10
    else:
        feedback_parts.append(f"First name mismatch: {user_data.get('first_name')}")
        
    if user_data.get('last_name') == metadata.get('expected_lastname'):
        score += 10
    else:
        feedback_parts.append(f"Last name mismatch: {user_data.get('last_name')}")

    # Check Role (30 pts) - CRITICAL
    roles = user_data.get('roles', '')
    # WP-CLI returns 'shop_manager', serialized might contain it
    if forbidden_role in roles:
        score = 0
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "SECURITY FAILURE: Administrator role assigned! Task failed immediately."
        }
    
    if expected_role in roles:
        score += 30
        feedback_parts.append("Role correct")
    else:
        feedback_parts.append(f"Role incorrect: {roles}")

    # Check Password (10 pts)
    if password_valid == 'true':
        score += 10
        feedback_parts.append("Password verified")
    elif password_valid == 'unknown':
        feedback_parts.append("Password verification inconclusive (SQL fallback)")
    else:
        feedback_parts.append("Password incorrect")

    # 3. VLM Verification (20 pts)
    # Only if we have decent score already, check trajectory
    if score >= 40:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        
        if frames:
            vlm_res = query_vlm(prompt=TRAJECTORY_PROCESS_PROMPT, images=frames)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('workflow_completed') or parsed.get('role_selection_visible'):
                    score += 20
                    feedback_parts.append("Workflow confirmed visually")
                else:
                    feedback_parts.append("Visual workflow unclear")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }