#!/usr/bin/env python3
"""
Verifier for compare_add_friend_errors task.

Criteria:
1. File /sdcard/error_comparison.txt exists (20 pts)
2. File was created during task (20 pts)
3. File content contains two distinct error sections (30 pts)
4. VLM verifies inputs were actually typed and errors appeared (30 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compare_add_friend_errors(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timing
    output_exists = result_data.get("output_exists", False)
    created_during = result_data.get("file_created_during_task", False)
    file_content = result_data.get("file_content", "")

    if output_exists:
        score += 20
        feedback_parts.append("Output file created")
    else:
        feedback_parts.append("Output file NOT found")

    if created_during:
        score += 20
        feedback_parts.append("File created during task window")
    
    # 3. Analyze Content (Programmatic)
    # Looking for headers and some content
    content_lower = file_content.lower()
    has_malformed_header = "malformed" in content_lower
    has_nonexistent_header = "non-existent" in content_lower or "nonexistent" in content_lower
    
    # We expect some error text. Common keywords for email errors:
    error_keywords = ["invalid", "valid", "format", "found", "exist", "match", "error", "please"]
    has_error_text = any(k in content_lower for k in error_keywords)

    if has_malformed_header and has_nonexistent_header:
        score += 15
        feedback_parts.append("File structure correct (headers found)")
    
    if has_error_text and len(file_content) > 20:
        score += 15
        feedback_parts.append("File contains plausible error text")

    # 4. VLM Verification (Trajectory Analysis)
    # We need to see that the agent actually interacted with the Add Friend screen
    # and tried the specific inputs.
    
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    You are verifying an agent's interaction with an Android app "Flight Crew View".
    The task was to test two "Add Friend" error cases:
    1. Input "this-is-not-an-email" (Malformed)
    2. Input "ghost_user_999@example.com" (Non-existent)
    
    Review the screenshots.
    1. Did the agent navigate to an "Add Friend" or search screen?
    2. Is the text "this-is-not-an-email" visible in an input field in any frame?
    3. Is the text "ghost_user_999" visible in an input field in any frame?
    4. Did any error message (like a Toast, red text, or popup) appear after these inputs?
    
    Output JSON:
    {
        "navigated_to_add_friend": true/false,
        "typed_malformed_input": true/false,
        "typed_nonexistent_input": true/false,
        "error_message_seen": true/false
    }
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get("parsed", {})
        
        if parsed.get("navigated_to_add_friend"):
            vlm_score += 5
        if parsed.get("typed_malformed_input"):
            vlm_score += 10
        if parsed.get("typed_nonexistent_input"):
            vlm_score += 10
        if parsed.get("error_message_seen"):
            vlm_score += 5
            
        feedback_parts.append(f"VLM Verification: {vlm_score}/30 pts")
        
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback_parts.append("VLM check failed (assuming 0)")

    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }