#!/usr/bin/env python3
"""Verifier for fix_volume_shadowed_dependencies task.

This task requires the agent to fix a 'Module not found' error caused by
a bind mount shadowing the container's node_modules.

Success Criteria:
1. Container 'shadow-app' is running (30 pts)
2. App responds with 200 OK (30 pts)
3. Volume Configuration Correct (40 pts):
   - Must have an anonymous volume (or named volume) mounted at /app/node_modules
   - AND must still have the bind mount at /app (dev requirement)
   - AND host must NOT have node_modules (prevents 'npm install' on host bypass)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_volume_shadowed_dependencies(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Container Running (30 pts)
    container_running = result.get('container_running', False)
    if container_running:
        score += 30
        feedback_parts.append("Container running (+30)")
    else:
        feedback_parts.append("Container NOT running (0)")

    # 2. App Responding (30 pts)
    http_status = result.get('http_status', '000')
    app_response = result.get('app_response', '')
    
    if http_status == '200' and 'Hello from Docker' in app_response:
        score += 30
        feedback_parts.append("App responding correctly (+30)")
    else:
        feedback_parts.append(f"App check failed (HTTP {http_status})")

    # 3. Volume Configuration (40 pts)
    # We analyze inspect_data to verify the solution
    inspect_data = result.get('inspect_data', [])
    mount_score = 0
    mount_feedback = []
    
    if inspect_data and isinstance(inspect_data, list):
        container_info = inspect_data[0]
        mounts = container_info.get('Mounts', [])
        
        # Check for bind mount (Requirement: must persist)
        has_bind_mount = False
        for m in mounts:
            if m.get('Destination') == '/app' and m.get('Type') == 'bind':
                has_bind_mount = True
                break
        
        # Check for node_modules volume (Requirement: The Fix)
        # Looking for a volume mounted at /app/node_modules
        has_node_modules_volume = False
        for m in mounts:
            if m.get('Destination') == '/app/node_modules' and m.get('Type') == 'volume':
                has_node_modules_volume = True
                break
                
        # Check if user cheated by running npm install on host
        host_node_modules_exists = result.get('host_node_modules_exists', False)
        
        if host_node_modules_exists:
            mount_feedback.append("FAIL: 'npm install' detected on host. Dependencies must come from the container.")
        elif not has_bind_mount:
            mount_feedback.append("FAIL: Bind mount '.:/app' was removed. Hot reloading requirement not met.")
        elif has_node_modules_volume:
            mount_score = 40
            mount_feedback.append("Correct volume configuration: /app/node_modules is masked (+40)")
        else:
            mount_feedback.append("FAIL: /app/node_modules is still shadowed by the bind mount.")
    else:
        mount_feedback.append("Could not inspect container configuration.")

    score += mount_score
    feedback_parts.extend(mount_feedback)

    # Final Pass Logic
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }