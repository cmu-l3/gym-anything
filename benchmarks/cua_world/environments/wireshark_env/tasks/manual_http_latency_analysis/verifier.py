#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manual_http_latency_analysis(traj, env_info, task_info):
    """
    Verifies the Manual HTTP Latency Analysis task.
    
    Criteria:
    1. Report Accuracy (70 pts):
       - Network Latency (35 pts): Within 1ms of ground truth.
       - Server Latency (35 pts): Within 1ms of ground truth.
    2. Evidence (30 pts):
       - Screenshot exists (15 pts).
       - Report valid JSON and created during task (15 pts).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
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

    # Extract Data
    gt = result.get('ground_truth', {})
    user_data = result.get('user_report', {})
    checks = result.get('checks', {})
    
    gt_network = gt.get('network_latency', -1)
    gt_server = gt.get('server_latency', -1)
    
    user_network = user_data.get('network_latency_seconds')
    user_server = user_data.get('server_processing_seconds')
    
    # Tolerances
    TOLERANCE = 0.001 # 1ms
    
    score = 0
    feedback = []
    
    # 1. Verify Network Latency (35 pts)
    if user_network is not None and isinstance(user_network, (int, float)):
        diff = abs(user_network - gt_network)
        if diff <= TOLERANCE:
            score += 35
            feedback.append(f"Network Latency Correct (Delta: {diff:.6f}s)")
        else:
            feedback.append(f"Network Latency Incorrect (Reported: {user_network:.6f}s, Actual: {gt_network:.6f}s)")
    else:
        feedback.append("Network Latency missing or invalid in report")

    # 2. Verify Server Latency (35 pts)
    if user_server is not None and isinstance(user_server, (int, float)):
        diff = abs(user_server - gt_server)
        if diff <= TOLERANCE:
            score += 35
            feedback.append(f"Server Latency Correct (Delta: {diff:.6f}s)")
        else:
            feedback.append(f"Server Latency Incorrect (Reported: {user_server:.6f}s, Actual: {gt_server:.6f}s)")
    else:
        feedback.append("Server Latency missing or invalid in report")
        
    # 3. Evidence Checks (30 pts)
    if checks.get('evidence_exists'):
        score += 15
        feedback.append("Evidence screenshot found")
    else:
        feedback.append("Evidence screenshot NOT found")
        
    if checks.get('report_valid') and checks.get('report_created_in_task'):
        score += 15
        feedback.append("Valid JSON report created")
    elif not checks.get('report_valid'):
        feedback.append("Invalid JSON report format")
    elif not checks.get('report_created_in_task'):
        feedback.append("Report file stale (not created during task)")

    # 4. Final Pass Check
    # Must get both latencies correct to pass
    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }