#!/usr/bin/env python3
"""Verifier for hl7_latency_monitoring_router task."""

import json
import tempfile
import os

def verify_hl7_latency_monitoring_router(traj, env_info, task_info):
    """
    Verify the latency monitoring channel.
    Scoring relies on the functional test performed by export_result.sh inside the container.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Channel Exists (20 pts)
    if result.get('channel_exists', False):
        score += 20
        feedback_parts.append("Channel 'Latency_Monitor' exists.")
    else:
        feedback_parts.append("Channel 'Latency_Monitor' NOT found.")

    # 2. Channel Deployed (20 pts)
    if result.get('channel_deployed', False):
        score += 20
        feedback_parts.append("Channel is deployed and running.")
    else:
        feedback_parts.append("Channel is NOT deployed/running.")

    # 3. High Latency Routing (30 pts)
    func_test = result.get('functional_test', {})
    if func_test.get('high_latency_routed_correctly', False):
        score += 30
        feedback_parts.append("High latency messages routed correctly.")
    else:
        feedback_parts.append("High latency routing FAILED (check logic or destination).")

    # 4. Normal Latency Routing (30 pts)
    if func_test.get('normal_latency_routed_correctly', False):
        score += 30
        feedback_parts.append("Normal latency messages routed correctly.")
    else:
        feedback_parts.append("Normal latency routing FAILED.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }