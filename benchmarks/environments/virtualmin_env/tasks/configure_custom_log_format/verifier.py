#!/usr/bin/env python3
import json
import os
import re
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_custom_log_format(traj, env_info, task_info):
    """
    Verify that the user configured a custom Apache LogFormat with %D and applied it.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Verify Apache is running (Critical)
    if not result.get('apache_running', False):
        return {"passed": False, "score": 0, "feedback": "Apache is not running."}
    score += 10
    feedback.append("Apache is running")

    # Decode Data
    try:
        global_config = base64.b64decode(result.get('global_config_b64', '')).decode('utf-8', errors='ignore')
        vhost_config = base64.b64decode(result.get('vhost_config_b64', '')).decode('utf-8', errors='ignore')
        log_tail = base64.b64decode(result.get('log_tail_b64', '')).decode('utf-8', errors='ignore')
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error decoding data: {str(e)}"}

    # 2. Verify Global LogFormat Definition (30 pts)
    # Regex for: LogFormat "..." latency_trace
    # We look for %D inside the quotes
    # Example: LogFormat "%h %l ... %D" latency_trace
    
    # Simple check for nickname presence
    has_nickname = "latency_trace" in global_config
    
    # Check for %D in the definition associated with latency_trace
    # This regex looks for LogFormat, then a quoted string containing %D, then the nickname
    # OR LogFormat, quoted string, nickname, where quoted string has %D.
    # Apache config syntax: LogFormat "format string" nickname
    
    log_format_regex = re.compile(r'LogFormat\s+"([^"]*)"\s+latency_trace', re.IGNORECASE)
    match = log_format_regex.search(global_config)
    
    if match:
        format_string = match.group(1)
        if "%D" in format_string or "%T" in format_string: # %D is microsec, %T is seconds (sometimes accepted as latency)
            score += 30
            feedback.append("Global LogFormat 'latency_trace' defined correctly with latency token")
        else:
            score += 15
            feedback.append("Global LogFormat 'latency_trace' defined, but missing latency token (%D)")
    else:
        feedback.append("Global LogFormat 'latency_trace' NOT found in apache2.conf")

    # 3. Verify Virtual Host Application (30 pts)
    # Look for CustomLog ... latency_trace in the vhost config
    if "latency_trace" in vhost_config and "CustomLog" in vhost_config:
        # stricter check
        if re.search(r'CustomLog\s+.*latency_trace', vhost_config):
            score += 30
            feedback.append("Virtual server configured to use 'latency_trace'")
        else:
            score += 10
            feedback.append("Virtual server config mentions 'latency_trace' but syntax looks wrong")
    else:
        feedback.append("Virtual server 'acmecorp.test' does NOT use 'latency_trace'")

    # 4. Functional Verification (30 pts)
    # Check the actual log file tail for a number at the end of the line
    # The setup script generates a request. 
    # Standard combined ends with "User Agent", latency_trace adds a number after.
    # Line format regex: ... "User Agent" 12345
    
    lines = log_tail.strip().split('\n')
    valid_lines = 0
    if lines:
        last_line = lines[-1]
        # Look for digits at the very end of the line
        if re.search(r'\s\d+$', last_line):
            valid_lines += 1
            
    if valid_lines > 0:
        score += 30
        feedback.append("Functional check passed: Logs contain latency values")
    else:
        feedback.append("Functional check failed: Last log entry does not end with a latency number")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": ". ".join(feedback)
    }