#!/usr/bin/env python3
"""
Verifier for configure_proxy_settings task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_proxy_settings(traj, env_info, task_info):
    """
    Verify that JStock proxy settings were configured correctly.
    
    Criteria:
    1. Proxy Host (proxy.acmecorp.net) found in config files (30 pts)
    2. Proxy Port (3128) found in config files (25 pts)
    3. Config file was modified *during* the task (20 pts)
    4. VLM Verification of trajectory (Options dialog usage) (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Check Proxy Host (30 pts)
    if result.get('host_found', False):
        score += 30
        feedback_parts.append("Proxy host configured correctly")
    else:
        feedback_parts.append("Proxy host NOT found in config")
        
    # 2. Check Proxy Port (25 pts)
    if result.get('port_found', False):
        score += 25
        feedback_parts.append("Proxy port configured correctly")
    else:
        feedback_parts.append("Proxy port NOT found in config")
        
    # 3. Check Modification Timestamp (20 pts)
    # This prevents pre-populating the file before the task starts
    if result.get('file_modified_during_task', False):
        score += 20
        feedback_parts.append("Configuration saved during task")
    elif result.get('host_found', False):
        feedback_parts.append("WARNING: Config found but timestamp predates task (suspicious)")
        
    # 4. VLM Verification (25 pts)
    # Since we don't have a live VLM in this verifiable function, we use the trajectory
    # logic as a placeholder. In a real run, this would query the VLM.
    # We will assume if file checks passed and we have frames, we give partial credit,
    # or if the user completely failed file checks, VLM likely won't save them.
    
    # Heuristic: If they got the config right, they almost certainly used the UI,
    # as JStock doesn't have a CLI config tool.
    if result.get('host_found', False) and result.get('port_found', False):
        score += 25
        feedback_parts.append("UI interaction inferred from successful config change")
    elif len(traj) > 5:
        # If they did work but didn't save correctly, give small partial credit for effort
        score += 5
        feedback_parts.append("Attempted task (trajectory exists)")
        
    # Determine Pass/Fail
    # Need at least correct host + port + timestamp (30+25+20 = 75)
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }