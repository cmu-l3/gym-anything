#!/usr/bin/env python3
"""
Verifier for test_api_endpoints_http task.

CRITERIA:
1. .http file creation (20 pts)
2. Valid GET request defined (20 pts)
3. Valid POST request defined (20 pts)
4. GET request actually executed against server (20 pts)
5. POST request actually executed against server (20 pts)

Uses VLM to confirm UI interaction.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_api_testing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result
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
    
    # --- Criterion 1: File Existence (20 pts) ---
    if result.get('http_file_exists'):
        score += 20
        feedback_parts.append(f"File created: {result.get('http_file_name')}")
    else:
        feedback_parts.append("No .http file found")
        # Fail early if file doesn't exist? No, check logs in case they used scratch file
    
    # --- Criterion 2 & 3: Content Analysis (40 pts) ---
    content = result.get('http_content', '')
    
    # Check for GET
    if re.search(r'GET\s+.*api/books', content, re.IGNORECASE):
        score += 20
        feedback_parts.append("GET request defined")
    else:
        feedback_parts.append("GET request definition not found in file")

    # Check for POST
    if re.search(r'POST\s+.*api/books', content, re.IGNORECASE):
        has_json_header = 'application/json' in content
        has_body = '{' in content and '}' in content
        
        if has_json_header and has_body:
            score += 20
            feedback_parts.append("POST request defined correctly (w/ header & body)")
        else:
            score += 10
            feedback_parts.append("POST request defined but missing header or body")
    else:
        feedback_parts.append("POST request definition not found in file")

    # --- Criterion 4 & 5: Server Execution Verification (40 pts) ---
    # This checks if the agent *actually* ran the requests against the live server
    logs = result.get('server_logs', '')
    
    # Check GET execution
    if "REQUEST\tGET /api/books" in logs:
        score += 20
        feedback_parts.append("GET request executed successfully")
    else:
        feedback_parts.append("GET request NOT received by server")

    # Check POST execution
    if "REQUEST\tPOST /api/books" in logs:
        # Check if body was valid JSON (server logs BODY)
        if "BODY\t" in logs and "{" in logs and "}" in logs:
            score += 20
            feedback_parts.append("POST request executed successfully")
        else:
            score += 10
            feedback_parts.append("POST request received but body was empty/invalid")
    else:
        feedback_parts.append("POST request NOT received by server")

    # --- VLM Verification (Optional but recommended for robust feedback) ---
    vlm_feedback = ""
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, num_samples=5)
            final = get_final_screenshot(traj)
            if final:
                frames.append(final)
                
            prompt = """
            You are verifying a task where an agent uses IntelliJ IDEA's HTTP Client.
            Look for:
            1. An editor window showing an .http file.
            2. Green 'Run' arrow icons in the gutter next to requests.
            3. A 'Services' or 'Run' tool window at the bottom showing JSON output (like a list of books).
            
            Did the agent execute the HTTP requests and see the output?
            """
            
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get('success'):
                vlm_feedback = f"VLM Analysis: {vlm_res.get('response', '')[:100]}..."
                
                # Bonus points for clear visual evidence if score is borderline
                parsed = vlm_res.get('parsed', {})
                if score < 80 and "yes" in vlm_res.get('response', '').lower():
                     score += 5
                     feedback_parts.append("VLM confirmed visual execution")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # Final tally
    passed = score >= 80  # Requires most steps to be correct
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) + (f" ({vlm_feedback})" if vlm_feedback else "")
    }