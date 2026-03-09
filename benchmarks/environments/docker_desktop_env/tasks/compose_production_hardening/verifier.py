#!/usr/bin/env python3
"""Verifier for compose_production_hardening task.

Scoring (100 points):
- Health checks all 3 services (25 pts): full if 3/3; partial 15pts for 2/3; 8pts for 1/3
- Resource limits all 3 services (25 pts): full if 3/3; partial 15pts for 2/3; 8pts for 1/3
- Restart policies all 3 services (20 pts): full if 3/3; partial 12pts for 2/3; 6pts for 1/3
- Network isolation (20 pts): frontend+backend defined (10pts) + redis only on backend (10pts)
- App accessible (10 pts): HTTP 200 on port 9080

Pass threshold: 70 points
Mandatory for pass: health checks >= 2 services + resource limits >= 2 + app accessible
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_compose_production_hardening(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/compose_production_hardening_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    details = {}

    compose_modified = result.get("compose_modified", False)
    hc_count = result.get("services_with_healthcheck", 0)
    limit_count = result.get("services_with_limits", 0)
    restart_count = result.get("services_with_restart", 0)
    has_frontend = result.get("has_frontend_network", False)
    has_backend = result.get("has_backend_network", False)
    redis_only_backend = result.get("redis_only_backend", False)
    http_code = result.get("app_http_code", "000")

    # Anti-gaming: if compose was never modified and no hardening done, score = 0
    if not compose_modified and hc_count == 0 and limit_count == 0 and restart_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "docker-compose.yml was not modified — no hardening applied",
            "details": {"compose_modified": False}
        }

    # Criterion 1: Health checks (25 pts)
    if hc_count >= 3:
        score += 25
        feedback_parts.append("Health checks on all 3 services (+25)")
    elif hc_count == 2:
        score += 15
        feedback_parts.append(f"Health checks on 2/3 services (+15)")
    elif hc_count == 1:
        score += 8
        feedback_parts.append(f"Health check on 1/3 services (+8)")
    else:
        feedback_parts.append("No health checks defined (+0)")
    details["services_with_healthcheck"] = hc_count

    # Criterion 2: Resource limits (25 pts)
    if limit_count >= 3:
        score += 25
        feedback_parts.append("Resource limits on all 3 services (+25)")
    elif limit_count == 2:
        score += 15
        feedback_parts.append(f"Resource limits on 2/3 services (+15)")
    elif limit_count == 1:
        score += 8
        feedback_parts.append(f"Resource limits on 1/3 services (+8)")
    else:
        feedback_parts.append("No resource limits defined (+0)")
    details["services_with_limits"] = limit_count

    # Criterion 3: Restart policies (20 pts)
    if restart_count >= 3:
        score += 20
        feedback_parts.append("Restart policies on all 3 services (+20)")
    elif restart_count == 2:
        score += 12
        feedback_parts.append(f"Restart policies on 2/3 services (+12)")
    elif restart_count == 1:
        score += 6
        feedback_parts.append(f"Restart policy on 1/3 services (+6)")
    else:
        feedback_parts.append("No restart policies defined (+0)")
    details["services_with_restart"] = restart_count

    # Criterion 4: Network isolation (20 pts)
    network_score = 0
    if has_frontend and has_backend:
        network_score += 10
        feedback_parts.append("Frontend and backend networks defined (+10)")
    elif has_frontend or has_backend:
        network_score += 5
        feedback_parts.append("Only one custom network defined (+5)")
    else:
        feedback_parts.append("No network isolation (frontend/backend networks missing) (+0)")

    if redis_only_backend:
        network_score += 10
        feedback_parts.append("Redis isolated to backend network only (+10)")
    elif has_backend:
        feedback_parts.append("Redis not exclusively on backend (+0)")

    score += network_score
    details["has_frontend_network"] = has_frontend
    details["has_backend_network"] = has_backend
    details["redis_only_backend"] = redis_only_backend

    # Criterion 5: App accessible after hardening (10 pts)
    # Only award points if the compose was actually modified (prevents do-nothing gaming)
    if compose_modified and http_code in ("200", "301", "302"):
        score += 10
        feedback_parts.append(f"App accessible HTTP {http_code} on port 9080 after hardening (+10)")
    elif not compose_modified:
        feedback_parts.append("App accessible but compose not modified — no hardening applied (+0)")
    else:
        feedback_parts.append(f"App not accessible on port 9080 (HTTP {http_code}) (+0)")
    details["app_http_code"] = http_code

    # Pass: >=2 health checks + >=2 limits + app accessible + score >= 70
    passed = hc_count >= 2 and limit_count >= 2 and (http_code in ("200", "301", "302")) and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
