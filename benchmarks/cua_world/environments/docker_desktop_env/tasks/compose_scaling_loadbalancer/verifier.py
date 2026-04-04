#!/usr/bin/env python3
"""
Verifier for compose_scaling_loadbalancer task.

Scoring Criteria (100 points total):
1. Service Health (40 pts)
   - 3 Flask replicas running (25 pts)
   - Nginx running (10 pts)
   - Redis running (5 pts)
2. Functional Load Balancing (30 pts)
   - Verified >1 unique hostnames in curl responses (20 pts)
   - Redis counter incrementing (state shared) (10 pts)
3. Configuration Correctness (20 pts)
   - docker-compose.yml has 'replicas: 3' (10 pts)
   - No 'container_name' in Flask service (conflicts with scaling) (5 pts)
   - Nginx config attempts load balancing (upstream/resolver) (5 pts)
4. Evidence (10 pts)
   - Verification file created by agent (5 pts)
   - Files modified after task start (5 pts)

Pass Threshold: 70 points AND (3 replicas running OR load balancing functional)
"""

import json
import tempfile
import os
import logging
import yaml

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compose_scaling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    
    # 1. Service Health (40 pts)
    flask_count = result.get('flask_containers_running', 0)
    nginx_running = result.get('nginx_running', 0)
    redis_running = result.get('redis_running', 0)
    
    if flask_count == 3:
        score += 25
        feedback_parts.append("3 Flask replicas running (+25)")
    elif flask_count > 1:
        score += 15
        feedback_parts.append(f"{flask_count} Flask replicas running (partial +15)")
    else:
        feedback_parts.append(f"Only {flask_count} Flask replica running (+0)")

    if nginx_running > 0:
        score += 10
        feedback_parts.append("Nginx running (+10)")
    else:
        feedback_parts.append("Nginx NOT running (+0)")

    if redis_running > 0:
        score += 5
        feedback_parts.append("Redis running (+5)")

    # 2. Functional Load Balancing (30 pts)
    unique_hosts = result.get('unique_hosts_observed', 0)
    redis_working = result.get('redis_working', False)
    
    if unique_hosts >= 2:
        score += 20
        feedback_parts.append(f"Load balancing verified ({unique_hosts} hosts) (+20)")
    else:
        feedback_parts.append("Load balancing failed (only 1 host observed) (+0)")
        
    if redis_working:
        score += 10
        feedback_parts.append("Shared Redis state verified (+10)")

    # 3. Configuration Correctness (20 pts)
    compose_content = result.get('compose_file_content', '')
    
    # Parse YAML safely
    try:
        compose_yaml = yaml.safe_load(compose_content)
        flask_service = compose_yaml.get('services', {}).get('flask', {})
        
        # Check replicas
        replicas = 0
        deploy = flask_service.get('deploy', {})
        if isinstance(deploy, dict):
            replicas = deploy.get('replicas', 0)
        
        if replicas == 3:
            score += 10
            feedback_parts.append("Compose config: replicas=3 (+10)")
        else:
            feedback_parts.append(f"Compose config: replicas={replicas}, expected 3 (+0)")
            
        # Check container_name (must NOT exist for replicas)
        if 'container_name' not in flask_service:
            score += 5
            feedback_parts.append("Compose config: container_name removed (+5)")
        else:
            feedback_parts.append("Compose config: container_name still present (prevents scaling) (+0)")
            
    except Exception as e:
        feedback_parts.append("Invalid docker-compose.yml syntax (+0)")

    # Nginx config heuristic from bash script
    if result.get('nginx_has_resolver_heuristic', False):
        score += 5
        feedback_parts.append("Nginx config: resolver/upstream detected (+5)")
    else:
        feedback_parts.append("Nginx config: no resolver/upstream detected (+0)")

    # 4. Evidence (10 pts)
    if result.get('verification_file_exists', False):
        score += 5
        feedback_parts.append("Verification file created (+5)")
        
    if result.get('compose_modified', False) or result.get('nginx_modified', False):
        score += 5
        feedback_parts.append("Files modified during task (+5)")

    # Pass logic
    # Must achieve pass threshold AND have either multiple replicas running OR functional LB
    # (Functional LB implies replicas are running, but just having replicas running is a good partial state)
    passed = score >= 70 and (flask_count == 3 or unique_hosts >= 2)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }