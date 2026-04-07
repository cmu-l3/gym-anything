#!/usr/bin/env python3
"""
Verifier for docker_compose_merge task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_compose_merge(traj, env_info, task_info):
    """
    Verify that the two Docker Compose projects were merged successfully.
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
    
    # 1. Compose file exists (5 pts)
    if result.get('compose_file_exists'):
        score += 5
        feedback_parts.append("Compose file created (+5)")
    else:
        feedback_parts.append("Compose file missing")
        return {"passed": False, "score": 0, "feedback": "Compose file missing", "details": result}

    # 2. Service Status (10 pts each, max 60)
    services = result.get('services_status', {})
    running_count = 0
    
    # Auth API
    if services.get('auth_api') == 'running':
        score += 10
        running_count += 1
        feedback_parts.append("Auth API running (+10)")
    else:
        feedback_parts.append("Auth API not running")

    # Catalog API
    if services.get('catalog_api') == 'running':
        score += 10
        running_count += 1
        feedback_parts.append("Catalog API running (+10)")
    else:
        feedback_parts.append("Catalog API not running")
        
    # Auth DB (detected via environment vars)
    if services.get('auth_db') == 'running':
        score += 10
        running_count += 1
        feedback_parts.append("Auth DB running (+10)")
    else:
        feedback_parts.append("Auth DB not running")

    # Catalog DB
    if services.get('catalog_db') == 'running':
        score += 10
        running_count += 1
        feedback_parts.append("Catalog DB running (+10)")
    else:
        feedback_parts.append("Catalog DB not running")

    # Redis
    if services.get('redis') == 'running':
        score += 10
        running_count += 1
        feedback_parts.append("Redis running (+10)")
    
    # Search
    if services.get('search') == 'running':
        score += 10
        running_count += 1
        feedback_parts.append("Search service running (+10)")

    # 3. Health Checks (10 pts each)
    health = result.get('health_checks', {})
    if health.get('auth_api') == 'passed':
        score += 10
        feedback_parts.append("Auth API healthy (+10)")
    else:
        feedback_parts.append("Auth API unhealthy")

    if health.get('catalog_api') == 'passed':
        score += 10
        feedback_parts.append("Catalog API healthy (+10)")
    else:
        feedback_parts.append("Catalog API unhealthy")

    # 4. Conflict Resolution (15 pts)
    if result.get('unique_ports'):
        score += 10
        feedback_parts.append("Unique ports assigned (+10)")
    else:
        feedback_parts.append("Port conflict detected")

    if result.get('unique_service_names'):
        score += 5
        feedback_parts.append("Unique service names (+5)")
    else:
        feedback_parts.append("Duplicate service names in compose")

    # Pass/Fail determination
    # Threshold: 65 points (e.g., all services running + file exists)
    pass_threshold = 65
    passed = score >= pass_threshold
    
    # Extra check: Must have at least one of each critical type running
    critical_ok = (services.get('auth_api') == 'running' and 
                   services.get('catalog_api') == 'running')
    
    if not critical_ok and passed:
        # Penalize if critical APIs aren't running even if score is high (unlikely with this rubric but safe)
        passed = False
        feedback_parts.append("FAILED: Both APIs must be running")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }