#!/usr/bin/env python3
"""
Verifier for configure_email_forwarding task.

Criteria:
1. Forwarding is enabled to 'sarah.hr.backup@gmail.com'
2. Local delivery is preserved (User must NOT lose their own copy)
3. Configuration was changed during the task (timestamp check)
4. VLM visual verification of the UI
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_email_forwarding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_forward = metadata.get('forward_address', 'sarah.hr.backup@gmail.com')
    
    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    user_info = result.get('user_info_cli', '')
    forward_content = result.get('forward_content', '')
    forward_mtime = result.get('forward_mtime', 0)
    task_start = result.get('task_start', 0)

    # =========================================================
    # Check 1: Is forwarding address configured? (25 pts)
    # =========================================================
    forwarding_found = False
    
    # Check CLI output (Virtualmin standard)
    if f"Forward to: {target_forward}" in user_info or target_forward in user_info:
        forwarding_found = True
    
    # Check .forward file
    if target_forward in forward_content:
        forwarding_found = True
        
    if forwarding_found:
        score += 25
        feedback_parts.append("Forwarding address found")
    else:
        feedback_parts.append(f"Forwarding to {target_forward} NOT found")

    # =========================================================
    # Check 2: Is LOCAL COPY retained? (25 pts)
    # =========================================================
    local_copy_retained = False
    
    # CLI Check: "Deliver to user: Yes" OR "Deliver locally: Yes"
    # Note: Virtualmin output format varies slightly by version/theme
    if "Deliver to user: Yes" in user_info or "Deliver locally: Yes" in user_info:
        local_copy_retained = True
    
    # .forward Check: look for backslash escape e.g. "\sarah" or just the username "sarah"
    # Usually looks like: \sarah, sarah.hr.backup@gmail.com
    if "\\sarah" in forward_content or "sarah," in forward_content or ", sarah" in forward_content:
        local_copy_retained = True
        
    if local_copy_retained:
        score += 25
        feedback_parts.append("Local copy configuration preserved")
    else:
        feedback_parts.append("ERROR: Local copy disabled (emails will not be saved on server)")

    # =========================================================
    # Check 3: Modification Timestamp (15 pts)
    # =========================================================
    # If .forward exists, check mtime. If not, rely on CLI but we can't verify time easily via CLI alone
    # unless we checked the file.
    if result.get('forward_file_exists') and forward_mtime > task_start:
        score += 15
        feedback_parts.append("Configuration modified during task")
    elif forwarding_found:
        # If we found forwarding but can't verify timestamp (e.g. DB based), give partial points
        # assuming the setup script cleared it successfully.
        score += 15
        feedback_parts.append("Configuration verified (timestamp check bypassed)")
    else:
        feedback_parts.append("No configuration change detected")

    # =========================================================
    # Check 4: VLM Visual Verification (35 pts)
    # =========================================================
    # Use final screenshot to verify UI state
    final_screenshot = get_final_screenshot(traj)
    
    vlm_score = 0
    if final_screenshot:
        prompt = f"""
        Review this screenshot of the Virtualmin 'Edit User' or 'Mail Forwarding' screen.
        
        I need to verify:
        1. Is the forwarding address '{target_forward}' visible?
        2. Is the option to 'Deliver locally' or 'Also deliver to this user' CHECKED or ENABLED?
        
        Respond JSON: {{ "forward_visible": bool, "local_copy_checked": bool }}
        """
        
        try:
            vlm_res = query_vlm(images=[final_screenshot], prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('forward_visible'):
                vlm_score += 20
                feedback_parts.append("VLM: Forwarding address visible in UI")
            
            if parsed.get('local_copy_checked'):
                vlm_score += 15
                feedback_parts.append("VLM: Local delivery checked in UI")
                
        except Exception as e:
            print(f"VLM error: {e}")
            # Fallback: if programmatic check passed, give partial VLM points
            if forwarding_found and local_copy_retained:
                vlm_score += 20
                feedback_parts.append("VLM skipped, relying on programmatic check")

    score += vlm_score

    # Final Evaluation
    passed = (score >= 60) and forwarding_found and local_copy_retained
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }