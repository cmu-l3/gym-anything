#!/usr/bin/env python3
"""
Verifier for Docker Healthcheck Configuration task.

Scoring (100 points):
  - product-catalog (Node): Healthy=20, Starting=10, Unhealthy=5
  - order-service (Python): Healthy=20, Starting=10, Unhealthy=5
  - db (Postgres): Healthy=20, Starting=10, Unhealthy=5
  - cache (Redis): Healthy=20, Starting=10, Unhealthy=5
  - Restart policies set on all: 10
  - Evidence file valid: 10

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_docker_healthcheck_config(traj, env_info, task_info):
    """Verify healthchecks and restart policies."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/healthcheck_results.json", temp_path)
            with open(temp_path, "r") as f:
                results = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    
    # Service Definitions
    services = {
        'catalog': ('product-catalog', 20),
        'orders': ('order-service', 20),
        'db': ('db', 20),
        'cache': ('cache', 20),
    }

    all_have_restart_policy = True
    all_exist = True

    # 1. Verify Services (80 points total)
    for key, (name, max_pts) in services.items():
        info = results.get(key, {})
        
        if not info.get('exists', False):
            feedback_parts.append(f"{name}: Missing (0/{max_pts})")
            all_exist = False
            all_have_restart_policy = False
            continue

        restart_policy = info.get('restart_policy', 'no')
        if restart_policy in ('', 'no'):
            all_have_restart_policy = False
        
        has_hc = info.get('has_healthcheck', False)
        health_status = info.get('health_status', 'none')

        if not has_hc:
            feedback_parts.append(f"{name}: No healthcheck configured (0/{max_pts})")
        else:
            if health_status == 'healthy':
                score += max_pts
                feedback_parts.append(f"{name}: Healthy (+{max_pts})")
            elif health_status == 'starting':
                # Partial credit if it's correctly configured but still initializing
                pts = max_pts // 2
                score += pts
                feedback_parts.append(f"{name}: Starting (+{pts}/{max_pts})")
            elif health_status == 'unhealthy':
                # Minimal credit for trying, but failing check
                pts = max_pts // 4
                score += pts
                feedback_parts.append(f"{name}: Unhealthy (+{pts}/{max_pts})")
            else:
                feedback_parts.append(f"{name}: Health status '{health_status}' (0/{max_pts})")

    # 2. Verify Restart Policies (10 points)
    if all_exist and all_have_restart_policy:
        score += 10
        feedback_parts.append("Restart policies: Configured (+10)")
    else:
        feedback_parts.append("Restart policies: Incomplete (0/10)")

    # 3. Verify Evidence File (10 points)
    report = results.get('report', {})
    if (report.get('exists') and report.get('has_content') and 
        report.get('after_start') and report.get('mentions_healthy')):
        score += 10
        feedback_parts.append("Evidence file: Valid (+10)")
    elif report.get('exists'):
        score += 5
        feedback_parts.append("Evidence file: Exists but invalid content/timestamp (5/10)")
    else:
        feedback_parts.append("Evidence file: Missing (0/10)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }