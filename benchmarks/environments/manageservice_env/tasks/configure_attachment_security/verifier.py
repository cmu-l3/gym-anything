#!/usr/bin/env python3
"""
Verifier for configure_attachment_security task.

Checks:
1. Primary: Database contains the restricted file extensions in the global configuration.
2. Secondary: VLM verifies the agent navigated to security settings and entered the data.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_attachment_security(traj, env_info, task_info):
    """
    Verify that the agent configured file attachment security settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load required extensions from metadata
    metadata = task_info.get('metadata', {})
    required_extensions = set(metadata.get('forbidden_extensions', ["exe", "bat", "cmd", "vbs", "sh"]))

    # 1. Load DB Result from Container
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
    
    # 2. Analyze Database Dump
    # The dump contains key-value pairs from GlobalConfig. We look for the extensions.
    db_dump = result.get('db_config_dump', '')
    found_exts = []
    
    # Check each required extension in the DB dump
    # We do case-insensitive check
    db_dump_lower = db_dump.lower()
    for ext in required_extensions:
        if ext.lower() in db_dump_lower:
            found_exts.append(ext)
    
    # DB Scoring
    if len(found_exts) == len(required_extensions):
        score += 50
        feedback_parts.append(f"Database confirmed all extensions blocked: {found_exts}")
    elif len(found_exts) > 0:
        partial = int(50 * (len(found_exts) / len(required_extensions)))
        score += partial
        feedback_parts.append(f"Database confirmed some extensions blocked: {found_exts}")
    else:
        feedback_parts.append("Database check failed: No blocked extensions found in configuration.")

    # 3. VLM Verification (Trajectory Analysis)
    # Essential because DB schema might vary or dump might miss a specific table.
    # We verify the workflow: Admin -> Security -> Inputting 'exe', 'bat', etc.
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    prompt = f"""
    You are verifying an IT Admin task in ManageEngine ServiceDesk Plus.
    The goal was to BLOCK file attachments with these extensions: {', '.join(required_extensions)}.
    
    Look at the screenshots and determine:
    1. Did the agent navigate to an Admin or Security Settings page?
    2. Is there a "File Attachment" or "Restricted Extensions" section visible?
    3. Did the agent type or add 'exe', 'bat', 'cmd', etc. into a restricted list?
    4. Did they save the settings?
    
    Provide a confidence score (0-100) and reasoning.
    """
    
    vlm_result = query_vlm(images=frames + [final_frame], prompt=prompt)
    
    vlm_score = 0
    if vlm_result and isinstance(vlm_result, dict):
        # We expect the VLM utility to return a structured dict or we parse the text
        # Assuming query_vlm returns a dict with 'score' or we parse it.
        # For safety, we trust the DB more, but VLM adds points if DB failed or confirms.
        
        # Simple heuristic if VLM returns text: look for positive keywords
        response_text = str(vlm_result).lower()
        if "yes" in response_text and "exe" in response_text:
            vlm_score = 40
        elif "yes" in response_text:
            vlm_score = 20
            
        # If the output format of query_vlm is standardized (e.g. JSON inside text), parse it
        # Here we assume a robust prompt response or add manual parsing logic if needed
        # For this template, we'll assign points based on DB success mostly, 
        # but if DB failed (0 points) and VLM says yes, we give partial credit (up to 40).
        
    # Combine scores
    # If DB confirmed everything, we are good (ignore VLM noise).
    # If DB confirmed partial/nothing, VLM can boost.
    
    if score >= 50:
        # DB passed, add navigation points
        score += 50 # Assume navigation was correct if DB updated
        feedback_parts.append("Configuration verified successfully.")
    else:
        # DB failed, check VLM backup
        score += vlm_score
        if vlm_score > 0:
            feedback_parts.append(f"VLM visual verification found evidence ({vlm_score} pts), but DB check failed.")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }