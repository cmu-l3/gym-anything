#!/usr/bin/env python3
"""Verifier for local_registry_image_workflow task.

Scoring (100 points):
- Registry running on port 5000 (20 pts): registry:2 container running and API accessible
- v1.0.0 tag in registry (20 pts): localhost:5000/v2/api-service/tags/list contains v1.0.0
- latest tag in registry (15 pts): tags/list contains latest
- Compose uses registry image (20 pts): docker-compose.yml uses image: localhost:5000/api-service (not build:)
- API accessible on port 7080 (25 pts): HTTP 200 on port 7080

Pass threshold: 70 points
Mandatory for pass: registry running + v1.0.0 in registry + API accessible
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_local_registry_image_workflow(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/local_registry_image_workflow_result.json", tmp.name)
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

    registry_running = result.get("registry_running", False)
    registry_accessible = result.get("registry_accessible", False)
    has_v100 = result.get("has_v100_tag", False)
    has_latest = result.get("has_latest_tag", False)
    compose_uses_registry = result.get("compose_uses_registry", False)
    compose_has_build = result.get("compose_has_build", False)
    http_code = result.get("api_http_code", "000")

    # Criterion 1: Registry running and accessible (20 pts)
    if registry_accessible:
        score += 20
        feedback_parts.append("Local registry running and accessible on port 5000 (+20)")
    elif registry_running:
        score += 10
        feedback_parts.append("Registry container running but API not accessible on port 5000 (+10)")
    else:
        feedback_parts.append("No local registry running on port 5000 (+0)")
    details["registry_accessible"] = registry_accessible

    # Criterion 2: v1.0.0 tag in registry (20 pts)
    if has_v100:
        score += 20
        feedback_parts.append("localhost:5000/api-service:v1.0.0 found in registry (+20)")
    else:
        feedback_parts.append("v1.0.0 tag not found in local registry (+0)")
    details["has_v100_tag"] = has_v100

    # Criterion 3: latest tag in registry (15 pts)
    if has_latest:
        score += 15
        feedback_parts.append("localhost:5000/api-service:latest found in registry (+15)")
    else:
        feedback_parts.append("latest tag not found in local registry (+0)")
    details["has_latest_tag"] = has_latest

    # Criterion 4: Compose uses registry image (20 pts)
    if compose_uses_registry and not compose_has_build:
        score += 20
        feedback_parts.append("docker-compose.yml uses registry image (not build:) (+20)")
    elif compose_uses_registry and compose_has_build:
        score += 10
        feedback_parts.append("Compose has registry image but also has build: directive — remove build: (+10)")
    else:
        feedback_parts.append("docker-compose.yml does not use localhost:5000/api-service image (+0)")
    details["compose_uses_registry"] = compose_uses_registry

    # Criterion 5: API accessible (25 pts)
    if http_code in ("200", "301", "302"):
        score += 25
        feedback_parts.append(f"API accessible HTTP {http_code} on port 7080 (+25)")
    else:
        feedback_parts.append(f"API not accessible on port 7080 (HTTP {http_code}) (+0)")
    details["api_http_code"] = http_code

    # Pass: registry accessible + v1.0.0 in registry + API accessible + score >= 70
    passed = registry_accessible and has_v100 and (http_code in ("200", "301", "302")) and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
