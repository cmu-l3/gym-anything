#!/usr/bin/env python3
"""
Verifier for investigate_concurrent_sessions task.

Verifies:
1. Agent created the required text file in the correct location.
2. The file was created AFTER the task started (anti-gaming).
3. The file contains the exactly injected IP addresses (not the dummy ones from the prompt).
4. VLM verifies the trajectory to ensure UI navigation occurred.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent performing a forensic IT task.
The agent was tasked with navigating the Safe Exam Browser Server monitoring UI to find IP addresses for a user named 'alex_rogue'.

Review these frames from the agent's workflow and determine:
1. Did the agent navigate to the Monitoring, Sessions, or Logs section of the UI?
2. Is there evidence the agent searched or filtered for the user 'alex_rogue'?
3. Did the agent view a screen displaying IP addresses?

Respond in JSON format ONLY:
{
    "navigated_monitoring": true/false,
    "searched_user": true/false,
    "viewed_ips": true/false,
    "confidence": "high/medium/low"
}
"""

def verify_investigate_concurrent_sessions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_ips = metadata.get('expected_ips', ["192.168.100.42", "10.0.55.201"])
    dummy_ips = ["203.0.113.45", "198.51.100.12"]

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check File Existence and Timestamps (Anti-Gaming)
    file_exists = result.get('file_exists', False)
    task_start = result.get('task_start_time', 0)
    file_mtime = result.get('file_mtime', 0)
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Output file rogue_ips.txt was not created."}
    
    score += 10
    feedback_parts.append("File exists")
    
    if file_mtime >= task_start:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("WARNING: File predates task start (Possible cheating)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Check File Content
    file_content = result.get('file_content', '')
    content_lower = file_content.lower()
    
    found_expected = 0
    for ip in expected_ips:
        if ip in content_lower:
            found_expected += 1
            
    hallucinated_dummy = False
    for ip in dummy_ips:
        if ip in content_lower:
            hallucinated_dummy = True
            
    if hallucinated_dummy:
        feedback_parts.append("FAIL: Agent hallucinated dummy IPs from the prompt instead of finding actual logs.")
        # Cap score to fail if they just copied the prompt
        return {"passed": False, "score": min(score, 30), "feedback": " | ".join(feedback_parts)}

    if found_expected == 0:
        feedback_parts.append("No correct IPs found in file")
    elif found_expected < len(expected_ips):
        score += 30
        feedback_parts.append(f"Found {found_expected}/{len(expected_ips)} correct IPs")
    else:
        score += 60  # All IPs found
        feedback_parts.append("All expected IPs found")

    # 4. Trajectory VLM Verification (Did they actually use the UI?)
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
        
        if vlm_result and vlm_result.get("parsed"):
            parsed = vlm_result["parsed"]
            if parsed.get("navigated_monitoring", False):
                score += 10
            if parsed.get("searched_user", False) or parsed.get("viewed_ips", False):
                score += 10
                feedback_parts.append("VLM verified UI workflow")
            else:
                feedback_parts.append("VLM did not clearly see the user search in UI")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # Be generous if VLM fails but data was perfectly extracted
        if found_expected == len(expected_ips):
            score += 20 

    # Determine Pass/Fail
    # To pass: must have found both IPs and have file created during task
    passed = (score >= 80) and (found_expected == len(expected_ips))

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }