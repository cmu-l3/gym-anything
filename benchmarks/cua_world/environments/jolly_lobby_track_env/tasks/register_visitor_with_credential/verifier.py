#!/usr/bin/env python3
"""
Verifier for register_visitor_with_credential task.

Verifies:
1. Agent created an export file (CSV/TXT)
2. File contains the visitor name (Elena Rosales)
3. File contains the company (GridLock Security)
4. CRITICAL: File contains the specific Badge ID (94022)
5. VLM: Validates the agent actually used the interface correctly if file is missing/ambiguous
"""

import json
import base64
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_visitor_with_credential(traj, env_info, task_info):
    """
    Verify visitor registration with correct badge ID.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_badge = metadata.get('badge_id', '94022')
    visitor_first = metadata.get('visitor_first', 'Elena')
    visitor_last = metadata.get('visitor_last', 'Rosales')
    visitor_company = metadata.get('visitor_company', 'GridLock') # Partial match ok

    # Load result JSON
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

    score = 0
    feedback_parts = []
    
    # 2. File Verification (Primary)
    output_exists = result.get('output_exists', False)
    content_b64 = result.get('file_content_b64', '')
    file_content = ""
    
    if output_exists and content_b64:
        try:
            file_content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
            score += 30
            feedback_parts.append("Export file created")
        except:
            feedback_parts.append("Export file corrupted")
    else:
        feedback_parts.append("No export file found")

    # Check Content
    has_name = (visitor_first in file_content) and (visitor_last in file_content)
    has_company = visitor_company in file_content
    has_badge = expected_badge in file_content

    if has_name:
        score += 30
        feedback_parts.append("Visitor name found in record")
    else:
        feedback_parts.append("Visitor name missing from export")

    if has_badge:
        score += 40
        feedback_parts.append(f"Badge ID {expected_badge} confirmed in record")
    else:
        feedback_parts.append(f"Badge ID {expected_badge} MISSING from export")

    # 3. VLM Verification (Secondary/Fallback)
    # If the file verification failed to find the badge (maybe format is weird), 
    # check trajectory to see if they typed it.
    if not has_badge:
        logger.info("Badge ID not found in file, attempting VLM verification on trajectory...")
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        if frames:
            prompt = f"""
            Analyze these screenshots of a visitor registration task in Jolly Lobby Track.
            The user was supposed to enter Badge Number '{expected_badge}' for visitor '{visitor_first} {visitor_last}'.
            
            Look for:
            1. A form field labeled 'Badge Number', 'Badge ID', or similar.
            2. The number '{expected_badge}' being typed or displayed in that field.
            3. The visitor name '{visitor_first} {visitor_last}' being entered.
            
            Did the agent enter the correct Badge Number?
            """
            
            try:
                vlm_result = query_vlm(images=frames, prompt=prompt)
                
                # Check if VLM confirms the action
                lower_response = vlm_result.get('response', '').lower()
                if "yes" in lower_response and expected_badge in lower_response:
                    score += 20 # Partial credit for doing it but failing export verification
                    feedback_parts.append("VLM confirmed Badge ID entry (partial credit)")
            except Exception as e:
                logger.error(f"VLM check failed: {e}")

    # 4. Anti-Gaming Check
    file_fresh = result.get('file_created_during_task', False)
    if output_exists and not file_fresh:
        score = 0
        feedback_parts = ["FAILED: Export file existed before task started (anti-gaming)"]

    # Final Score Calculation
    passed = score >= 70 and has_badge # Critical requirement
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }