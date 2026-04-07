#!/usr/bin/env python3
"""
Verifier for service_selector_reconciliation task.

Scoring (100 points total, 25 points per service):
- Criterion 1 (25 pts): `order-api` has >= 1 endpoint AND `order-api-deploy` has >= 1 ready replica.
- Criterion 2 (25 pts): `tracking-svc` has >= 1 endpoint AND `tracking-deploy` has >= 1 ready replica.
- Criterion 3 (25 pts): `inventory-svc` has >= 1 endpoint AND `inventory-deploy` has >= 1 ready replica.
- Criterion 4 (25 pts): `notification-hub` has >= 1 endpoint AND `notification-deploy` has >= 1 ready replica.

Pass threshold: 70 points (3 out of 4 services successfully restored).

Anti-gaming:
- The `ready_replicas` check ensures the agent cannot simply delete the Deployments and create dummy standalone pods to satisfy the Service selectors.
- The Endpoints check verifies that the Service's selector and the Deployment pod templates now match and traffic can route.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/service_selector_reconciliation_result.json"
PASS_THRESHOLD = 70

def verify_service_selector_reconciliation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable in env_info"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run successfully.",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result JSON: {e}"}

    score = 0
    feedback_parts = []
    
    services = result.get("services", {})
    deployments = result.get("deployments", {})

    pairs = [
        ("order-api", "order-api-deploy", "Typo in selector"),
        ("tracking-svc", "tracking-deploy", "Wrong role value"),
        ("inventory-svc", "inventory-deploy", "Extra label component: inventory-mgr"),
        ("notification-hub", "notification-deploy", "Version drift v2 vs v1")
    ]

    for svc_name, dep_name, desc in pairs:
        eps_ready = services.get(svc_name, {}).get("ready_endpoints", 0)
        dep_ready = deployments.get(dep_name, {}).get("ready_replicas", 0)
        
        if eps_ready >= 1 and dep_ready >= 1:
            score += 25
            feedback_parts.append(
                f"PASS: {svc_name} restored ({eps_ready} endpoints, {dep_ready} ready replicas) [+25]"
            )
        else:
            reasons = []
            if eps_ready < 1:
                reasons.append(f"0 endpoints (selector mismatch remains)")
            if dep_ready < 1:
                reasons.append(f"0 ready replicas in {dep_name}")
                
            feedback_parts.append(
                f"FAIL: {svc_name} not restored - {', '.join(reasons)} [0]"
            )

    passed = score >= PASS_THRESHOLD
    
    # Check if the agent did nothing
    if score == 0:
        feedback_parts.append("CRITICAL: All services still have 0 endpoints. Check label/selector relationships.")
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }