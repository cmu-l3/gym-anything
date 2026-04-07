#!/usr/bin/env python3
"""
Verifier for docker_service_scaling task.

Scoring (100 points):
  - Multiple API replicas running (20 pts)
  - Exactly 3 replicas (5 pts)
  - Load balancing working (distinct hostnames > 1) (25 pts)
  - Nginx upstream/resolver configured (15 pts)
  - API endpoint healthy (10 pts)
  - Failover resilience (15 pts)
  - Report exists and valid (10 pts)

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_docker_service_scaling(traj, env_info, task_info):
    """Verify Docker service scaling and load balancing."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/task_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Replica Count (Max 25)
    replicas = result.get("api_replicas", 0)
    if replicas >= 2:
        score += 20
        feedback_parts.append(f"Multiple replicas running ({replicas}) (+20)")
        if replicas == 3:
            score += 5
            feedback_parts.append("Target of 3 replicas met (+5)")
    else:
        feedback_parts.append(f"Insufficient replicas: {replicas} (expected >= 2)")

    # 2. Load Balancing (Max 25)
    distinct_hosts = result.get("distinct_hostnames_count", 0)
    api_working = result.get("api_working", 0)
    
    if api_working:
        if distinct_hosts > 1:
            score += 25
            feedback_parts.append(f"Load balancing verified ({distinct_hosts} distinct hosts) (+25)")
        else:
            feedback_parts.append("API working but only hitting 1 instance - load balancing failed (0/25)")
    else:
        feedback_parts.append("API not reachable (0/25)")

    # 3. API Health (10)
    if api_working:
        score += 10
        feedback_parts.append("API endpoint healthy (+10)")

    # 4. Nginx Configuration (Max 15)
    # They need either upstream block OR resolver+variable to do this right in Docker
    has_resolver = result.get("nginx_has_resolver", False)
    has_upstream = result.get("nginx_has_upstream", False)
    has_vars = result.get("nginx_has_variables", False)
    
    if has_resolver or (has_upstream and replicas > 1):
        score += 15
        feedback_parts.append("Nginx configuration correct (+15)")
    else:
        feedback_parts.append("Nginx config missing resolver or upstream block (0/15)")

    # 5. Failover (Max 15)
    failover = result.get("failover_success", False)
    if failover:
        score += 15
        feedback_parts.append("Failover test passed (+15)")
    else:
        feedback_parts.append("Failover test failed (0/15)")

    # 6. Report (Max 10)
    report_exists = result.get("report_exists", False)
    report_size = result.get("report_size", 0)
    
    if report_exists and report_size > 50:
        score += 10
        feedback_parts.append("Report exists (+10)")
    elif report_exists:
        score += 5
        feedback_parts.append("Report empty/short (+5)")
    else:
        feedback_parts.append("No report found (0/10)")

    passed = score >= 60 and distinct_hosts > 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }