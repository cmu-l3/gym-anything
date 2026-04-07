#!/usr/bin/env python3
"""
Verifier for channel_watchdog_autostarter task.
Verifies that the agent created a self-healing system using Mirth Connect channels.
"""

import json
import base64
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_channel_watchdog_autostarter(traj, env_info, task_info):
    """
    Verify the watchdog implementation.
    
    Criteria:
    1. 'Unstable_Service' channel exists (10 pts)
    2. 'System_Watchdog' channel exists (10 pts)
    3. Watchdog polling frequency is reasonable (5-20s) (10 pts)
    4. Auto-restart functionality works (dynamic test) (50 pts)
    5. Log file exists and contains entries (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy result file
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
            
    # Extract data
    target_exists = result.get("target_exists", False)
    watchdog_exists = result.get("watchdog_exists", False)
    polling_interval = result.get("polling_interval", 0)
    auto_restart_success = result.get("auto_restart_success", False)
    log_exists = result.get("log_exists", False)
    log_has_content = result.get("log_has_content", False)
    log_content_b64 = result.get("log_content_base64", "")
    
    score = 0
    feedback_parts = []
    
    # 1. Channel Existence
    if target_exists:
        score += 10
        feedback_parts.append("'Unstable_Service' channel found")
    else:
        feedback_parts.append("'Unstable_Service' channel MISSING")
        
    if watchdog_exists:
        score += 10
        feedback_parts.append("'System_Watchdog' channel found")
    else:
        feedback_parts.append("'System_Watchdog' channel MISSING")
        
    # 2. Polling Config
    # Expecting around 10000ms. Allow 1000ms to 60000ms.
    try:
        poll_val = int(polling_interval)
        if 1000 <= poll_val <= 60000:
            score += 10
            feedback_parts.append(f"Polling frequency acceptable ({poll_val}ms)")
        elif poll_val > 0:
            score += 5
            feedback_parts.append(f"Polling frequency suboptimal ({poll_val}ms)")
        else:
            feedback_parts.append("Polling frequency not detected or zero")
    except:
        feedback_parts.append("Invalid polling frequency value")

    # 3. Dynamic Test (The most important part)
    if auto_restart_success:
        score += 50
        feedback_parts.append("SUCCESS: Watchdog automatically restarted the stopped service")
    else:
        feedback_parts.append("FAIL: Watchdog did NOT restart the service when tested")
        
    # 4. Logging
    if log_exists and log_has_content:
        score += 20
        feedback_parts.append("Log file created and contains entries")
        
        # Optional: check content
        try:
            log_text = base64.b64decode(log_content_b64).decode('utf-8')
            if "Restart" in log_text or "Unstable" in log_text:
                feedback_parts.append("Log content looks correct")
        except:
            pass
    elif log_exists:
        score += 10
        feedback_parts.append("Log file exists but is empty")
    else:
        feedback_parts.append("Log file not found")
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }