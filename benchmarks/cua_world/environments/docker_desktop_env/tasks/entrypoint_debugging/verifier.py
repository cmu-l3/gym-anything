#!/usr/bin/env python3
"""
Verifier for entrypoint_debugging task.

Scoring Breakdown (100 pts):
1. Operational State (45 pts)
   - Gateway running: 10
   - API running: 10
   - Worker running: 10
   - All 3 running: +15 bonus

2. Functional Correctness (45 pts)
   - Gateway responds 200: 15
   - API responds healthy: 15
   - Worker uses correct interval (5s): 15

3. Fix Verification (10 pts)
   - Files were actually modified (anti-gaming): 10

Pass Threshold: 70 points AND All 3 containers running.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_entrypoint_debugging(traj, env_info, task_info):
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

    score = 0
    feedback_parts = []
    
    # 1. Operational State (45 pts)
    gateway_running = result.get("gateway_status") == "running"
    api_running = result.get("api_status") == "running"
    worker_running = result.get("worker_status") == "running"
    
    if gateway_running: score += 10
    if api_running: score += 10
    if worker_running: score += 10
    
    if gateway_running and api_running and worker_running:
        score += 15
        feedback_parts.append("All containers running (+45)")
    else:
        feedback_parts.append(f"Containers running: Gateway={gateway_running}, API={api_running}, Worker={worker_running}")

    # 2. Functional Correctness (45 pts)
    # Gateway Accessibility
    if result.get("gateway_http_code") == "200":
        score += 15
        feedback_parts.append("Gateway accessible (+15)")
    else:
        feedback_parts.append(f"Gateway failed (HTTP {result.get('gateway_http_code')})")

    # API Health
    if result.get("api_healthy"):
        score += 15
        feedback_parts.append("API healthy (+15)")
    else:
        feedback_parts.append("API health check failed")

    # Worker Logic
    if result.get("worker_interval_correct"):
        score += 15
        feedback_parts.append("Worker interval correct (5s) (+15)")
    else:
        feedback_parts.append("Worker interval incorrect (CMD args ignored)")

    # 3. Anti-Gaming / Fix Verification (10 pts)
    # Ensure they actually edited the files and didn't just hack the compose file 
    # (though hacking compose is valid if it solves the problem, the Dockerfile fixes are the intended path)
    if result.get("files_modified"):
        score += 10
        feedback_parts.append("Configuration files modified (+10)")
    else:
        feedback_parts.append("No configuration files modified (Anti-gaming check)")

    # Pass logic
    all_running = gateway_running and api_running and worker_running
    passed = all_running and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }