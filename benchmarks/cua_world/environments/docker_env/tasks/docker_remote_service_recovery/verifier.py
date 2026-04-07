#!/usr/bin/env python3
import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remote_recovery(traj, env_info, task_info):
    """
    Verifies that the agent successfully recovered the remote service.
    
    Criteria:
    1. Docker context 'staging' created pointing to correct host (20 pts)
    2. Broken container replaced (running state) on REMOTE host (30 pts)
    3. Correct Environment Variable set (20 pts)
    4. Correct Port Mapping preserved (10 pts)
    5. Correct Image used (10 pts)
    6. Cleanup (10 pts) - implicitly checked if new one is running and name collision didn't happen
    
    Anti-gaming:
    - Container must be on remote host, not local.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check Context (20 pts)
    if result.get("context_exists"):
        endpoint = result.get("context_endpoint", "")
        if "staging-node" in endpoint and "2375" in endpoint:
            score += 20
            feedback.append("Docker context 'staging' created correctly.")
        else:
            score += 10
            feedback.append(f"Docker context created, but endpoint '{endpoint}' looks suspicious.")
    else:
        feedback.append("Docker context 'staging' not found.")

    # 2. Check Remote Container State (30 pts)
    if result.get("remote_container_running"):
        score += 30
        feedback.append("Service is running on remote host.")
    else:
        feedback.append("Service is NOT running on remote host.")

    # Anti-gaming check
    if result.get("local_container_running") == "true":
        score = 0
        return {"passed": False, "score": 0, "feedback": "FAILED: You started the container on the LOCAL machine, not the remote host."}

    # 3. Check Env Var (20 pts)
    if result.get("env_var_set"):
        score += 20
        feedback.append("Environment variable UPSTREAM_TARGET set.")
    else:
        feedback.append("Environment variable UPSTREAM_TARGET missing.")

    # 4. Check Port Mapping (10 pts)
    if result.get("port_mapped"):
        score += 10
        feedback.append("Port 8080:80 mapped correctly.")
    else:
        feedback.append("Port mapping incorrect.")

    # 5. Check Image (10 pts)
    if result.get("image_correct"):
        score += 10
        feedback.append("Correct image used.")
    else:
        feedback.append("Incorrect image used.")
        
    # 6. Cleanup (Implicit 10 pts)
    # If remote_container_running is true, they must have removed the old one 
    # (since we reused the name 'web-proxy').
    if result.get("remote_container_running"):
        score += 10
        feedback.append("Old container successfully replaced.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }