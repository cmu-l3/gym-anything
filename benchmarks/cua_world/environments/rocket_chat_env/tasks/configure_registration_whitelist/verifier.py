#!/usr/bin/env python3
"""
Verifier for configure_registration_whitelist task in Rocket.Chat.

Verification Strategy:
1. PRIMARY: Query the REST API for the specific modified 'Accounts' settings.
2. SECONDARY (Anti-gaming): Use VLM across trajectory frames to ensure the agent actually
   navigated the Administration > Workspace > Settings UI.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance on configuring Rocket.Chat settings.
The agent was instructed to navigate to Administration > Workspace > Settings > Accounts.

Look at these images sampled from the agent's trajectory.
Did the agent reach the Rocket.Chat "Administration" panel and specifically the "Settings" > "Accounts" area?
You should look for UI text/elements like "Registration", "Registration Form", "Allowed Domains List", or "Allow User Profile Change".

Respond with a JSON object:
{
    "reached_admin_accounts_settings": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is visible in the frames that confirms or refutes this"
}
"""

def verify_configure_registration_whitelist(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Evaluate VLM over trajectory frames
    query_vlm = env_info.get('query_vlm')
    vlm_points = 0
    vlm_feedback = "VLM verification not available"
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_result = query_vlm(images=images, prompt=VLM_PROMPT)
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('reached_admin_accounts_settings', False):
                        vlm_points = 20
                        vlm_feedback = "VLM confirmed agent navigated to Accounts settings"
                    else:
                        vlm_feedback = "VLM did not detect agent in Accounts settings"
                else:
                    vlm_feedback = f"VLM parsing failed: {vlm_result.get('error')}"
        except Exception as e:
            vlm_feedback = f"VLM Exception: {str(e)}"

    # Check exported REST API results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if not result:
        return {"passed": False, "score": 0, "feedback": "Result JSON is empty or missing"}

    metadata = task_info.get('metadata', {})
    expected_domains = metadata.get('expected_allowed_domains', 'rocketchat.local')
    expected_form = metadata.get('expected_registration_form', 'Public')
    
    score = vlm_points
    feedback_parts = [vlm_feedback]
    
    # 1. Registration Form Check (10 pts)
    actual_form = result.get('Accounts_RegistrationForm')
    if actual_form == expected_form:
        score += 10
        feedback_parts.append("Registration Form is correct")
    else:
        feedback_parts.append(f"Registration Form incorrect: {actual_form}")

    # 2. Allowed Domains Check (30 pts)
    actual_domains = str(result.get('Accounts_AllowedDomainsList', '')).strip()
    if actual_domains == expected_domains:
        score += 30
        feedback_parts.append(f"Allowed Domains correctly set to {expected_domains}")
    elif expected_domains in actual_domains:
        score += 15  # Partial credit if appended without replacing
        feedback_parts.append(f"Allowed Domains contains {expected_domains} but is not exact match")
    else:
        feedback_parts.append(f"Allowed Domains incorrect: {actual_domains}")

    # 3. Allow User Profile Change (20 pts)
    actual_prof = result.get('Accounts_AllowUserProfileChange')
    if actual_prof is False or str(actual_prof).lower() == 'false':
        score += 20
        feedback_parts.append("Profile Change correctly disabled")
    else:
        feedback_parts.append(f"Profile Change not disabled (is {actual_prof})")

    # 4. Allow Real Name Change (20 pts)
    actual_name = result.get('Accounts_AllowRealNameChange')
    if actual_name is False or str(actual_name).lower() == 'false':
        score += 20
        feedback_parts.append("Name Change correctly disabled")
    else:
        feedback_parts.append(f"Name Change not disabled (is {actual_name})")

    # Determine passing state (must achieve main goals and total score > 65)
    key_criteria_met = (actual_domains == expected_domains) and (actual_prof is False or actual_name is False)
    passed = (score >= 65) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }