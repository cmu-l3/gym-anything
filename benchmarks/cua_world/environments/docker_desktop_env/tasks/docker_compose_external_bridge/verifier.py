#!/usr/bin/env python3
"""
Verifier for docker_compose_external_bridge task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_compose_external_bridge(traj, env_info, task_info):
    """
    Verify the external network bridge configuration.
    
    Rubric (100 pts total):
    - 20 pts: Networks 'infra-db-net' and 'infra-cache-net' exist.
    - 20 pts: All 3 containers (postgres, redis, api) are running.
    - 20 pts: Network membership is correct (DB on db-net, Redis on cache-net, API on BOTH).
    - 30 pts: Functional connectivity (Health checks return 200 OK).
    - 10 pts: Connectivity report exists and files were modified correctly.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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

    score = 0
    feedback_parts = []
    
    # 1. Networks Exist (20 pts)
    nets = result.get("networks", {})
    if nets.get("infra-db-net") and nets.get("infra-cache-net"):
        score += 20
        feedback_parts.append("Networks created")
    elif nets.get("infra-db-net") or nets.get("infra-cache-net"):
        score += 10
        feedback_parts.append("One network missing")
    else:
        feedback_parts.append("Both networks missing")

    # 2. Containers Running (20 pts)
    ctrs = result.get("containers_running", {})
    running_count = sum([1 for k, v in ctrs.items() if v])
    if running_count == 3:
        score += 20
        feedback_parts.append("All containers running")
    else:
        partial = int((running_count / 3) * 20)
        score += partial
        feedback_parts.append(f"{running_count}/3 containers running")

    # 3. Network Membership (20 pts)
    mems = result.get("network_membership", {})
    mem_score = 0
    if mems.get("postgres_on_db_net"): mem_score += 5
    if mems.get("redis_on_cache_net"): mem_score += 5
    if mems.get("api_on_db_net"): mem_score += 5
    if mems.get("api_on_cache_net"): mem_score += 5
    score += mem_score
    
    if mem_score == 20:
        feedback_parts.append("Network configuration correct")
    else:
        feedback_parts.append("Network configuration incomplete")

    # 4. Functional Connectivity (30 pts)
    # This is the most important part - checks if DNS and routing actually work
    health = result.get("health_checks", {})
    db_ok = str(health.get("db_http_code")) == "200"
    redis_ok = str(health.get("redis_http_code")) == "200"
    
    if db_ok and redis_ok:
        score += 30
        feedback_parts.append("Connectivity verified (HTTP 200)")
    elif db_ok or redis_ok:
        score += 15
        feedback_parts.append("Partial connectivity verified")
    else:
        feedback_parts.append("Connectivity checks failed (API cannot reach DB/Redis)")

    # 5. Report & Anti-Gaming (10 pts)
    mod = result.get("files_modified", {})
    report = result.get("report", {})
    
    misc_score = 0
    if mod.get("infra_compose") and mod.get("api_compose"):
        misc_score += 5
    if report.get("exists"):
        misc_score += 5
    
    score += misc_score
    if misc_score < 10:
        feedback_parts.append("Report missing or files not modified")

    passed = (score >= 70) and db_ok and redis_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }