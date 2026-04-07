#!/usr/bin/env python3
"""
Verifier for configure_exec_module_trigger task.

Verification Strategy:
1. Script File existence & Linux +X permissions (20 points)
2. Script Logic - check for expected bash logic to append to correct log (10 points)
3. Background Service - `exec` module enabled and running (20 points)
4. Config: Subscriptions - module listens to LOCATION group (20 points)
5. Config: Trigger - module mapped Origin message to the script (30 points)

Pass threshold is 70/100, requiring a working script and valid config.
"""

import json
import tempfile
import os
import base64
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_exec_module(traj, env_info, task_info):
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_script = metadata.get('target_script_path', '/home/ga/scripts/log_origin.sh')
    expected_log = metadata.get('target_log_path', '/home/ga/origin_audit.log')

    # Load result exported from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Script File existence and permissions (20 points)
    # ---------------------------------------------------------
    script_exists = result.get("script_exists", False)
    script_executable = result.get("script_executable", False)
    script_content = ""
    
    if script_exists:
        try:
            script_content = base64.b64decode(result.get("script_content_b64", "")).decode('utf-8')
        except:
            pass

        if script_executable:
            score += 20
            feedback_parts.append("Script exists and is executable.")
        else:
            score += 10
            feedback_parts.append("Script exists but lacks executable permissions (+x).")
    else:
        feedback_parts.append("Hook script not found.")

    # ---------------------------------------------------------
    # 2. Script Logic (10 points)
    # ---------------------------------------------------------
    if script_exists and script_content:
        # Check if the script contains redirect/append to the audit log
        appends_log = expected_log in script_content and (">>" in script_content or "tee -a" in script_content)
        uses_arg = "$1" in script_content or "${1}" in script_content
        calls_date = "date" in script_content
        
        if appends_log and uses_arg and calls_date:
            score += 10
            feedback_parts.append("Script logic is fully correct.")
        elif appends_log and uses_arg:
            score += 8
            feedback_parts.append("Script appends argument to log, but might be missing timestamp logic.")
        elif appends_log:
            score += 5
            feedback_parts.append("Script appends to log but doesn't correctly use $1.")
        else:
            feedback_parts.append("Script logic incorrect (missing log append or $1 usage).")

    # ---------------------------------------------------------
    # 3. Service Status (20 points)
    # ---------------------------------------------------------
    exec_running = result.get("exec_running", False)
    exec_enabled = result.get("exec_enabled", False)
    
    if exec_running and exec_enabled:
        score += 20
        feedback_parts.append("Exec module is enabled and running.")
    elif exec_running or exec_enabled:
        score += 10
        feedback_parts.append("Exec module is either enabled or running, but not both.")
    else:
        feedback_parts.append("Exec module is NOT enabled or running.")

    # ---------------------------------------------------------
    # 4 & 5. Config Analysis (50 points combined)
    # ---------------------------------------------------------
    dump_cfg = result.get("dump_cfg", "")
    
    # Check Subscriptions (20 points)
    has_sub = False
    for line in dump_cfg.splitlines():
        if line.strip().startswith("subscriptions") and "LOCATION" in line:
            has_sub = True
            break
            
    if has_sub:
        score += 20
        feedback_parts.append("Subscribed to LOCATION group.")
    else:
        feedback_parts.append("Missing or incorrect LOCATION subscription.")

    # Check Trigger configuration (30 points)
    # scconfig exports profiles dynamically under "scripts.[profile_name].*"
    profile_names = set()
    
    # Match generic pattern for script definitions in dump output
    # e.g., scripts.myProfile.script = /home/ga/scripts/log_origin.sh
    script_pattern = re.compile(r"^scripts\.(\w+)\.script\s*=\s*(.*log_origin\.sh)")
    
    for line in dump_cfg.splitlines():
        m = script_pattern.match(line.strip())
        if m:
            profile_names.add(m.group(1))

    script_configured = len(profile_names) > 0
    message_configured = False
    
    # Validate the profile also filters for Origin messages
    if script_configured:
        for profile in profile_names:
            msg_pattern = re.compile(rf"^scripts\.{profile}\.message\s*=\s*Origin", re.IGNORECASE)
            for line in dump_cfg.splitlines():
                if msg_pattern.match(line.strip()):
                    message_configured = True
                    break
            if message_configured:
                break

    if script_configured and message_configured:
        score += 30
        feedback_parts.append("Trigger profile correctly maps Origin to script.")
    elif script_configured:
        score += 15
        feedback_parts.append("Script configured in exec, but missing Origin message filter.")
    else:
        feedback_parts.append("Trigger profile for the script not found in exec config.")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "script_exists": script_exists,
            "script_executable": script_executable,
            "exec_running": exec_running,
            "exec_enabled": exec_enabled,
            "has_subscription": has_sub,
            "trigger_configured": script_configured and message_configured
        }
    }