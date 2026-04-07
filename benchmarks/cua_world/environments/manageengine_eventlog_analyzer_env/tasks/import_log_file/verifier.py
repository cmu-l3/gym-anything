#!/usr/bin/env python3
"""
Verifier for import_log_file task.

Criteria:
1. Event count in database increased (Primary Signal).
2. VLM verifies the agent accessed the Import/Upload feature (Secondary Signal).
3. VLM verifies the agent selected the correct file (Secondary Signal).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_log_file(traj, env_info, task_info):
    """
    Verify that the log file was imported into EventLog Analyzer.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_event_increase = metadata.get('min_event_increase', 1)
    
    # 1. Load result from container
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
    
    # --- Criterion 1: Database Event Count Increase (40 points) ---
    increase = result.get('event_count_increase', 0)
    initial = result.get('initial_event_count', 0)
    current = result.get('current_event_count', 0)
    
    # Check if database query was successful (not all zeros if system is active)
    # If both are 0, DB query might have failed, relying on VLM more heavily
    db_query_active = not (initial == 0 and current == 0)
    
    if db_query_active:
        if increase >= min_event_increase:
            score += 40
            feedback_parts.append(f"Success: {increase} new events detected in database.")
        else:
            feedback_parts.append(f"Failure: Only {increase} new events detected (expected >={min_event_increase}).")
    else:
        feedback_parts.append("Warning: Database verification indeterminate (counts are zero). Relying on visual evidence.")
        # We'll reallocate points to VLM if DB is silent, or fail if strictly required.
        # For this task, we'll cap the score but allow passing if VLM is perfect.

    # --- Criterion 2: VLM Trajectory Verification (60 points) ---
    # We look for:
    # 1. Navigation to Import/Settings page
    # 2. File selection dialog or input
    # 3. Successful import message or table update
    
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying if an agent successfully imported a log file named 'auth.log' into a SIEM tool (EventLog Analyzer).
    
    Review the sequence of screenshots. Look for these specific steps:
    1. Navigation: Did the user go to an 'Import', 'Settings', or 'Add Device' section?
    2. File Selection: Did the user browse for or select a file named 'auth.log' (or similar path /home/ga/log_samples/auth.log)?
    3. Configuration: Did the user select 'Linux' or 'Syslog' format?
    4. Success: Is there a confirmation message, or did the event list update?
    
    Return a JSON object with:
    {
        "navigated_to_import": boolean,
        "selected_auth_log": boolean,
        "import_confirmed": boolean,
        "confidence": "low|medium|high",
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("navigated_to_import"):
            score += 20
            feedback_parts.append("Visual: Navigated to import section.")
        
        if parsed.get("selected_auth_log"):
            score += 20
            feedback_parts.append("Visual: Selected 'auth.log' file.")
            
        if parsed.get("import_confirmed"):
            score += 20
            feedback_parts.append("Visual: Import confirmed.")
            
        feedback_parts.append(f"VLM reasoning: {parsed.get('reasoning')}")
    else:
        feedback_parts.append("VLM analysis failed or was inconclusive.")

    # --- Final Scoring ---
    # If DB failed but VLM was perfect (60 pts), we might not pass.
    # We require at least one strong signal.
    # Pass threshold: 60 points.
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }