#!/usr/bin/env python3
"""
Verifier for stateful_network_identity_migration task.

Scoring (100 points total, Pass threshold: 75):
C1 (25 pts): Workload Kind Corrected — The Deployment must be gone, and the StatefulSet must exist.
C2 (25 pts): Service Linkage Configured — The StatefulSet must set .spec.serviceName = "hazelcast-discovery".
C3 (25 pts): Headless Service Established — The Service must exist and have clusterIP = "None".
C4 (25 pts): Pods Successfully Running — 3 pods must be in Running state, proving the hostname check passed.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/stateful_network_identity_migration_result.json"
PASS_THRESHOLD = 75


def verify_stateful_network_identity_migration(traj, env_info, task_info):
    """
    Verify that the agent migrated the hazelcast-mock from a Deployment to a Headless StatefulSet.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

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
            "feedback": "Result file not found — export script may not have run",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []

    # ── C1: Workload Kind Corrected (25 pts) ──────────────────────────────────
    deployment_count = int(result.get("deployment_count", 1))
    statefulset_count = int(result.get("statefulset_count", 0))

    if deployment_count == 0 and statefulset_count >= 1:
        score += 25
        feedback_parts.append("C1 PASS: Deployment deleted and StatefulSet created (+25)")
    else:
        reasons = []
        if deployment_count > 0:
            reasons.append("Deployment still exists")
        if statefulset_count == 0:
            reasons.append("StatefulSet not found")
        feedback_parts.append(f"C1 FAIL: Workload kind incorrect ({', '.join(reasons)})")

    # ── C2: Service Linkage Configured (25 pts) ───────────────────────────────
    sts_service_name = str(result.get("sts_service_name", ""))
    
    if sts_service_name == "hazelcast-discovery":
        score += 25
        feedback_parts.append("C2 PASS: StatefulSet explicitly linked to hazelcast-discovery service (+25)")
    else:
        feedback_parts.append(f"C2 FAIL: StatefulSet serviceName is '{sts_service_name}' (expected 'hazelcast-discovery')")

    # ── C3: Headless Service Established (25 pts) ─────────────────────────────
    service_exists = result.get("service_exists", False)
    service_cluster_ip = str(result.get("service_cluster_ip", ""))
    
    if service_exists and service_cluster_ip.lower() == "none":
        score += 25
        feedback_parts.append("C3 PASS: hazelcast-discovery Service is Headless (clusterIP: None) (+25)")
    else:
        if not service_exists:
            feedback_parts.append("C3 FAIL: hazelcast-discovery Service not found")
        else:
            feedback_parts.append(f"C3 FAIL: Service has clusterIP '{service_cluster_ip}' (expected 'None')")

    # ── C4: Pods Successfully Running (25 pts) ────────────────────────────────
    # The active anti-gaming constraint: the pods will only reach Running if they
    # pass the hostname check (name-[0-9]+).
    running_pods = int(result.get("running_pods", 0))
    total_pods = int(result.get("total_pods", 0))
    
    if running_pods >= 3:
        score += 25
        feedback_parts.append(f"C4 PASS: {running_pods} pod(s) are Running, proving the architecture provides stable network identities (+25)")
    else:
        feedback_parts.append(f"C4 FAIL: Only {running_pods}/{total_pods} pods are Running. (They will crash if not deployed as a StatefulSet).")

    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }