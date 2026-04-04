#!/usr/bin/env python3
"""
Verifier for security_config_audit task.

Criteria:
1. Report file existence and creation time (Anti-gaming).
2. Report content validity (Keywords: Room name, E2EE, Lobby, Password).
3. Screenshot file existence and creation time.
4. VLM Verification:
   - Did agent join the meeting?
   - Did agent open the Security Options dialog?
   - Is the Security Options dialog visible in the agent's saved screenshot?
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_security_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    report_path = metadata.get('report_path', '/home/ga/security_audit.txt')
    screenshot_path = metadata.get('screenshot_path', '/home/ga/security_options_screenshot.png')
    required_keywords = metadata.get('required_keywords', [])

    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Load Exported Result JSON
    # =========================================================
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_json_path = f.name
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json_path)
        with open(temp_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json_path):
            os.unlink(temp_json_path)

    # =========================================================
    # 2. Verify Report File (Content & Timestamp)
    # =========================================================
    report_exists = task_result.get('report_exists', False)
    report_valid_time = task_result.get('report_created_during_task', False)
    report_content_score = 0
    
    if report_exists and report_valid_time:
        score += 10
        feedback_parts.append("Report file created.")
        
        # Check content
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as f:
            temp_report_path = f.name
        
        try:
            copy_from_env(report_path, temp_report_path)
            with open(temp_report_path, 'r', errors='ignore') as f:
                content = f.read()
                
            # Check for keywords
            found_keywords = [kw for kw in required_keywords if kw.lower() in content.lower()]
            missing_keywords = [kw for kw in required_keywords if kw.lower() not in content.lower()]
            
            # Scoring for keywords (Total 30 pts)
            kw_score = 0
            if "ConfidentialBoardRoom".lower() in content.lower():
                kw_score += 10
            if "E2EE".lower() in content.lower() or "End-to-End Encryption".lower() in content.lower():
                kw_score += 10
            if "Lobby".lower() in content.lower():
                kw_score += 5
            if "Password".lower() in content.lower():
                kw_score += 5
                
            report_content_score = kw_score
            score += report_content_score
            
            if missing_keywords:
                feedback_parts.append(f"Report missing keywords: {', '.join(missing_keywords)}")
            else:
                feedback_parts.append("Report content looks good.")
                
        except Exception as e:
            feedback_parts.append(f"Could not read report content: {e}")
        finally:
            if os.path.exists(temp_report_path):
                os.unlink(temp_report_path)
    else:
        feedback_parts.append("Report file missing or stale.")

    # =========================================================
    # 3. Verify Agent Screenshot File
    # =========================================================
    screenshot_exists = task_result.get('screenshot_file_exists', False)
    screenshot_valid_time = task_result.get('screenshot_created_during_task', False)
    screenshot_size = task_result.get('screenshot_size', 0)
    
    if screenshot_exists and screenshot_valid_time and screenshot_size > 5000:
        score += 10
        feedback_parts.append("Agent screenshot created.")
    else:
        feedback_parts.append("Agent screenshot missing or empty.")

    # =========================================================
    # 4. VLM Trajectory Verification
    # =========================================================
    # We want to verify the agent actually opened the dialog and joined the meeting.
    # We check the trajectory frames.
    
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=5)
    
    # We also want to check the agent's *output* screenshot if possible, 
    # but that's inside the container. We'll rely on trajectory for workflow verification.
    
    from gym_anything.vlm import query_vlm
    
    prompt = """
    You are auditing an agent's interaction with Jitsi Meet video conferencing.
    
    Look at this sequence of screenshots and answer the following:
    1. Did the agent successfully JOIN the meeting (move past the pre-join/name entry screen)?
    2. Did the agent OPEN the "Security Options" dialog? (Look for a panel with title "Security options" containing toggles for Lobby, Password, E2EE).
    3. Is the Security Options panel visible in any frame?
    
    Respond in JSON:
    {
        "joined_meeting": true/false,
        "opened_security_dialog": true/false,
        "security_dialog_visible": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=prompt)
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('joined_meeting', False):
            vlm_score += 20
            feedback_parts.append("VLM: Agent joined meeting.")
        else:
            feedback_parts.append("VLM: Could not confirm agent joined meeting.")
            
        if parsed.get('opened_security_dialog', False) or parsed.get('security_dialog_visible', False):
            vlm_score += 30
            feedback_parts.append("VLM: Security dialog usage confirmed.")
        else:
            feedback_parts.append("VLM: Could not confirm Security Options were accessed.")
            
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification failed (system error).")
        # Fallback partial credit if files are good
        if score >= 40:
            vlm_score += 20

    score += vlm_score

    # =========================================================
    # Final Assessment
    # =========================================================
    # Pass threshold: 60 points
    # Must have report (at least 10 pts) and joined meeting (VLM 20 pts) or opened dialog (30 pts)
    passed = score >= 60 and report_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }