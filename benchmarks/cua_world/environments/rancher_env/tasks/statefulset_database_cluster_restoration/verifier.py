#!/usr/bin/env python3
"""
Verifier for statefulset_database_cluster_restoration task.

Scoring (100 points total):
- C1 (25 pts): StatefulSet postgres-cluster uses image postgres:15-alpine
- C2 (25 pts): Secret 'postgres-credentials' has key 'POSTGRES_PASSWORD'
- C3 (25 pts): StatefulSet containers have cpu AND memory resource requests set
- C4 (25 pts): Service 'postgres-cluster' has clusterIP: None (headless)

Pass threshold: 70 (any 3 of 4 criteria)

Anti-gaming analysis:
  Do-nothing: C1=0 (image=14), C2=0 (key=DB_PASSWORD), C3=0 (no requests), C4=0 (clusterIP set) → score=0
  Delete namespace: all checks return not-found/defaults → score=0
  Wrong namespace: rejected with score=0
  Rename secret: C2 checks only 'postgres-credentials' → score=0 on C2

Strategy enumeration:
  | Strategy          | C1 | C2 | C3 | C4 | Score | Pass? |
  | Do-nothing        |  0 |  0 |  0 |  0 |     0 | No    |
  | Fix C1 only       | 25 |  0 |  0 |  0 |    25 | No    |
  | Fix C1+C2         | 25 | 25 |  0 |  0 |    50 | No    |
  | Fix any 3         | 25 | 25 | 25 |  0 |    75 | Yes   |
  | Fix all 4         | 25 | 25 | 25 | 25 |   100 | Yes   |
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/statefulset_database_cluster_restoration_result.json"
PASS_THRESHOLD = 70


def verify_statefulset_database_cluster_restoration(traj, env_info, task_info):
    """
    Verify that the PostgreSQL StatefulSet cluster has been restored to spec.

    Scoring:
      C1: StatefulSet image is postgres:15-alpine                   25 pts
      C2: Secret has key POSTGRES_PASSWORD                          25 pts
      C3: StatefulSet has cpu and memory resource requests          25 pts
      C4: Service clusterIP is None (headless)                      25 pts
    Pass: >= 70
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
            "feedback": "Result file not found — export script did not run",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # Wrong-target guard
    if result.get("namespace") != "data-platform":
        return {
            "passed": False,
            "score": 0,
            "feedback": "Wrong namespace — must target 'data-platform'",
        }

    score = 0
    feedback_parts = []

    # ── Criterion 1: StatefulSet image must be postgres:15-alpine ─────────────
    sts = result.get("statefulset", {})
    image = str(sts.get("image", "")).strip()

    # Accept any variant of postgres:15-alpine (with or without registry prefix)
    image_ok = "postgres:15" in image and "alpine" in image

    if image_ok:
        score += 25
        feedback_parts.append(
            f"C1 PASS: StatefulSet uses image '{image}' (postgres:15-alpine) (+25)"
        )
    else:
        feedback_parts.append(
            f"C1 FAIL: StatefulSet image='{image}' — must be 'postgres:15-alpine' (not postgres:14)"
        )

    # ── Criterion 2: Secret must have key POSTGRES_PASSWORD ───────────────────
    secret = result.get("secret", {})
    has_pg_pass = str(secret.get("has_postgres_password", "false")).lower()
    secret_keys = secret.get("keys", [])

    if has_pg_pass == "true":
        score += 25
        feedback_parts.append(
            "C2 PASS: Secret 'postgres-credentials' has key 'POSTGRES_PASSWORD' (+25)"
        )
    else:
        feedback_parts.append(
            f"C2 FAIL: Secret 'postgres-credentials' missing key 'POSTGRES_PASSWORD' "
            f"(found keys: {secret_keys}) — rename 'DB_PASSWORD' to 'POSTGRES_PASSWORD'"
        )

    # ── Criterion 3: StatefulSet must have resource requests ──────────────────
    cpu_req = str(sts.get("cpu_request", "")).strip()
    mem_req = str(sts.get("memory_request", "")).strip()

    # Any non-empty cpu and memory request is acceptable
    has_cpu = bool(cpu_req)
    has_mem = bool(mem_req)

    if has_cpu and has_mem:
        score += 25
        feedback_parts.append(
            f"C3 PASS: StatefulSet has resource requests cpu='{cpu_req}', memory='{mem_req}' (+25)"
        )
    else:
        issues = []
        if not has_cpu:
            issues.append("missing cpu request")
        if not has_mem:
            issues.append("missing memory request")
        feedback_parts.append(
            f"C3 FAIL: StatefulSet containers missing resource requests — {'; '.join(issues)}"
        )

    # ── Criterion 4: Headless Service clusterIP must be None ──────────────────
    svc = result.get("headless_service", {})
    cluster_ip = str(svc.get("cluster_ip", "")).strip()

    headless_ok = cluster_ip.lower() == "none"

    if headless_ok:
        score += 25
        feedback_parts.append(
            "C4 PASS: Service 'postgres-cluster' has clusterIP: None (headless) (+25)"
        )
    else:
        feedback_parts.append(
            f"C4 FAIL: Service 'postgres-cluster' clusterIP='{cluster_ip}' — "
            f"must be 'None' for StatefulSet DNS to work (headless service required)"
        )

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
