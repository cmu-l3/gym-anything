#!/usr/bin/env python3
"""
Verifier for polyurethane_mixer_hmi_security task.

Uses a robust hybrid verification strategy:
1. File Integrity (Programmatic): Checks if 'reactor_secure.c3' was genuinely created during the task.
2. Workflow Verification (VLM): Uses trajectory frame sampling to prove the agent navigated multiple 
   functional modules (Security, Data Tags, Display Pages) to accomplish the safety configurations.
"""

import json
import os
import tempfile
import logging
import re

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    sample_trajectory_frames = None
    get_final_screenshot = None

logger = logging.getLogger(__name__)

# Note: Using forward slashes for cross-platform compatibility with container paths
RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/polyurethane_mixer_result.json"

def build_vlm_prompt():
    return """Examine these trajectory screenshots of an HMI configuration session in Red Lion Crimson 3.0.

Your task is to verify if the user successfully completed specific configurations across different modules (Security, Data Tags, Display Pages).

Look for evidence of the following:
1. SECURITY USER: Was a user created with User Name 'super' and granted 'User Right 2'? (Look at the Security navigation pane and user properties).
2. ALARM THRESHOLD: Was a tag (e.g., Reactor_Temp) configured with 'Alarm 1' set to Event Type 'Absolute High' with a Value of '180' or '180.0'? (Look at the Data Tags pane, Alarms tab).
3. ALARM PRIVILEGE: Was the 'Acknowledge' privilege for this alarm set to require 'User Right 2'?
4. UI PRIMITIVE: Was an 'Alarm Viewer' primitive placed onto a Display Page (Page 1)? (Look for a list/table-like UI element labeled 'Alarm Viewer' on the display canvas).

Respond ONLY with a JSON object in the exact format below:
{
    "user_super_created": true,
    "user_right_2_granted": true,
    "alarm_high_180": true,
    "ack_privilege_right_2": true,
    "alarm_viewer_placed": true,
    "observations": "Brief explanation of what you see to justify the boolean values"
}"""

def verify_polyurethane_mixer_hmi_security(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework Error: copy_from_env unavailable."}
        
    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. FILE INTEGRITY & ANTI-GAMING CHECK (Programmatic)
    # ================================================================
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result JSON not found. The export hook likely failed."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result JSON: {e}"}

    project_found = result.get("project_found", False)
    file_created = result.get("file_created_during_task", False)
    
    if not project_found:
        return {"passed": False, "score": 0, "feedback": "FAIL: Project file 'reactor_secure.c3' not found at the destination path."}
        
    if not file_created:
        return {"passed": False, "score": 0, "feedback": "FAIL: Project file exists but its timestamp precedes task start. (Do-Nothing detected)."}
        
    score += 10
    feedback_parts.append("File Integrity Verified (10/10)")

    # ================================================================
    # 2. TRAJECTORY WORKFLOW VERIFICATION (VLM)
    # ================================================================
    if not query_vlm or not sample_trajectory_frames or not get_final_screenshot:
        return {"passed": False, "score": score, "feedback": f"{feedback_parts[0]} | VLM utilities unavailable for visual verification."}

    # Sample trajectory to catch multi-module steps
    frames = sample_trajectory_frames(traj, n=6)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if not images:
        return {"passed": False, "score": score, "feedback": f"{feedback_parts[0]} | No trajectory screenshots available."}

    vlm_result = query_vlm(prompt=build_vlm_prompt(), images=images)
    
    if not vlm_result or not vlm_result.get("success"):
        return {"passed": False, "score": score, "feedback": f"{feedback_parts[0]} | VLM query execution failed."}
        
    parsed = vlm_result.get("parsed", {})
    if not parsed:
        # Fallback regex JSON extraction in case VLM included conversational text
        resp_text = vlm_result.get("response", "")
        try:
            json_match = re.search(r'\{.*\}', resp_text, re.DOTALL)
            if json_match:
                parsed = json.loads(json_match.group(0))
        except Exception:
            pass

    user_created = parsed.get("user_super_created", False)
    right_granted = parsed.get("user_right_2_granted", False)
    alarm_high = parsed.get("alarm_high_180", False)
    ack_priv = parsed.get("ack_privilege_right_2", False)
    viewer_placed = parsed.get("alarm_viewer_placed", False)
    
    # Assess Visual Milestones
    if user_created:
        score += 20
        feedback_parts.append("Supervisor User Created (20/20)")
    else:
        feedback_parts.append("Supervisor User Missing (0/20)")
        
    if right_granted:
        score += 15
        feedback_parts.append("User Right 2 Granted (15/15)")
    else:
        feedback_parts.append("User Right 2 Missing (0/15)")
        
    if alarm_high:
        score += 20
        feedback_parts.append("Alarm Configured to 180°C (20/20)")
    else:
        feedback_parts.append("Alarm Threshold Missing/Wrong (0/20)")
        
    if ack_priv:
        score += 15
        feedback_parts.append("Ack Privilege Configured (15/15)")
    else:
        feedback_parts.append("Ack Privilege Missing/Wrong (0/15)")
        
    if viewer_placed:
        score += 20
        feedback_parts.append("Alarm Viewer UI Placed (20/20)")
    else:
        feedback_parts.append("Alarm Viewer UI Missing (0/20)")

    # Must hit at least 70 points AND complete the core file integrity step
    passed = (score >= 70) and file_created
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": parsed
    }