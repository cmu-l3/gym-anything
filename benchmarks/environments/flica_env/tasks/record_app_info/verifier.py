#!/usr/bin/env python3
"""
Verifier for record_app_info task.

Checks:
1. File existence and creation timestamp (Anti-gaming).
2. File format (App Version: ... / Developer Email: ...).
3. Data correctness (Version matches installed app, Email matches dev).
4. VLM verification of navigation trajectory.
"""

import json
import base64
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_app_info(traj, env_info, task_info):
    """
    Verify that the agent correctly extracted app info and saved it to the file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- CRITERION 1: File Existence & Anti-Gaming (20 pts) ---
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file /sdcard/app_info_report.txt not found."}
    
    if result.get("file_created_during_task", False):
        score += 20
        feedback_parts.append("File created during task (+20)")
    else:
        # If file exists but timestamp is wrong, 0 points for this section but continue checking content
        feedback_parts.append("File timestamp invalid (pre-dates task)")

    # Decode content
    try:
        content_b64 = result.get("file_content_b64", "")
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except Exception:
        content = ""

    lines = [line.strip() for line in content.split('\n') if line.strip()]

    # --- CRITERION 2: Format Compliance (20 pts) ---
    has_version_header = any("app version:" in line.lower() for line in lines)
    has_email_header = any("developer email:" in line.lower() for line in lines)
    
    if has_version_header and has_email_header:
        score += 20
        feedback_parts.append("Correct file format (+20)")
    elif has_version_header or has_email_header:
        score += 10
        feedback_parts.append("Partial format match (+10)")
    else:
        feedback_parts.append("Incorrect file format")

    # --- CRITERION 3: Data Accuracy (40 pts) ---
    ground_truth = result.get("ground_truth", {})
    true_version = ground_truth.get("version", "").strip()
    true_email = ground_truth.get("email", "").strip()

    # Parse Agent Output
    agent_version = ""
    agent_email = ""
    
    for line in lines:
        if "app version:" in line.lower():
            agent_version = re.sub(r'(?i)app version:\s*', '', line).strip()
        if "developer email:" in line.lower():
            agent_email = re.sub(r'(?i)developer email:\s*', '', line).strip()

    # Check Version (20 pts)
    # Loose matching: check if true version is contained in agent output or vice versa
    if agent_version and (true_version in agent_version or agent_version in true_version):
        score += 20
        feedback_parts.append(f"Version correct: {agent_version} (+20)")
    else:
        feedback_parts.append(f"Version mismatch (Exp: {true_version}, Got: {agent_version})")

    # Check Email (20 pts)
    if agent_email and (true_email.lower() == agent_email.lower()):
        score += 20
        feedback_parts.append(f"Email correct: {agent_email} (+20)")
    elif agent_email and (true_email.split('@')[1].lower() in agent_email.lower()):
        # Partial credit for correct domain
        score += 10
        feedback_parts.append("Email domain matches (+10)")
    else:
        feedback_parts.append(f"Email mismatch (Exp: {true_email}, Got: {agent_email})")

    # --- CRITERION 4: VLM Trajectory Verification (20 pts) ---
    # We want to ensure the agent actually navigated to the About page
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    You are verifying an agent's workflow in an Android app.
    The goal was to navigate to Settings > About to find the App Version and Developer Email.
    
    Look at these screenshots of the agent's journey.
    1. Do you see the Flight Crew View main menu or home screen?
    2. Do you see a 'Settings' menu or option being selected?
    3. Do you see an 'About' screen or 'App Info' screen showing version numbers?
    
    Return JSON: {"navigated_settings": bool, "saw_about_screen": bool, "confidence": float}
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("saw_about_screen", False):
            score += 20
            feedback_parts.append("VLM confirmed navigation to About screen (+20)")
        elif parsed.get("navigated_settings", False):
            score += 10
            feedback_parts.append("VLM confirmed navigation to Settings only (+10)")
        else:
            feedback_parts.append("VLM could not verify navigation logic")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if data is correct, assume navigation happened (trust verify)
        if score >= 60: 
            score += 20
            feedback_parts.append("VLM failed but data correct -> assuming success (+20)")

    # Final Score Calculation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }