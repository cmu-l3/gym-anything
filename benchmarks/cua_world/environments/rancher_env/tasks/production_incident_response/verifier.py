#!/usr/bin/env python3
"""
Verifier for production_incident_response task.

Scoring (100 points total):
- Criterion 1 (25 pts): api-gateway has ≥1 Running pod (image was fixed)
- Criterion 2 (25 pts): web-frontend Service has ≥1 endpoint (selector mismatch fixed)
- Criterion 3 (25 pts): cache-layer ConfigMap REDIS_PORT corrected to "6379"
- Criterion 4 (25 pts): batch-processor has ≥1 Running pod (memory request reduced)

Pass threshold: 70 points (3 of 4 fixes required)

Anti-gaming:
- Wrong-target: namespace must be "ecommerce"
- Partial credit: each criterion independent
- Max partial total = 0 (no partial within criteria) < 70 threshold

Do-nothing score = 0 (all services broken at start).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/production_incident_response_result.json"
PASS_THRESHOLD = 70


def verify_production_incident_response(traj, env_info, task_info):
    """
    Verify that all 4 ecommerce service failures have been diagnosed and resolved.

    Scoring:
      C1: api-gateway running    25 pts
      C2: frontend has endpoints 25 pts
      C3: cache port corrected   25 pts
      C4: batch-processor running 25 pts
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
            "feedback": "Result file not found — export script may not have run",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # Validate correct namespace was targeted
    if result.get("namespace") != "ecommerce":
        return {
            "passed": False,
            "score": 0,
            "feedback": "Wrong namespace — actions must target the 'ecommerce' namespace",
        }

    score = 0
    feedback_parts = []

    # ── Criterion 1: api-gateway running ────────────────────────────────────
    api_gw = result.get("api_gateway", {})
    api_running = int(api_gw.get("pods_running", 0))
    api_image = api_gw.get("current_image", "")
    if api_running >= 1:
        score += 25
        feedback_parts.append(f"C1 PASS: api-gateway has {api_running} Running pod(s) [image: {api_image}] (+25)")
    else:
        feedback_parts.append(
            f"C1 FAIL: api-gateway has no Running pods — image '{api_image}' needs to be fixed"
        )

    # ── Criterion 2: web-frontend has endpoints ──────────────────────────────
    frontend = result.get("web_frontend", {})
    endpoint_count = int(frontend.get("endpoint_count", 0))
    if endpoint_count >= 1:
        score += 25
        feedback_parts.append(
            f"C2 PASS: web-frontend Service has {endpoint_count} endpoint(s) — selector mismatch fixed (+25)"
        )
    else:
        feedback_parts.append(
            "C2 FAIL: web-frontend Service has no endpoints — Service selector and pod labels do not match"
        )

    # ── Criterion 3: cache ConfigMap REDIS_PORT corrected ────────────────────
    cache = result.get("cache_layer", {})
    redis_port = str(cache.get("redis_port", ""))
    if redis_port == "6379":
        score += 25
        feedback_parts.append("C3 PASS: cache-layer ConfigMap REDIS_PORT corrected to 6379 (+25)")
    else:
        feedback_parts.append(
            f"C3 FAIL: cache-layer ConfigMap REDIS_PORT is '{redis_port}' — expected '6379'"
        )

    # ── Criterion 4: batch-processor running ─────────────────────────────────
    batch = result.get("batch_processor", {})
    batch_running = int(batch.get("pods_running", 0))
    batch_mem = batch.get("memory_request", "unknown")
    if batch_running >= 1:
        score += 25
        feedback_parts.append(
            f"C4 PASS: batch-processor has {batch_running} Running pod(s) [mem request: {batch_mem}] (+25)"
        )
    else:
        feedback_parts.append(
            f"C4 FAIL: batch-processor has no Running pods [mem request: {batch_mem}] — "
            "reduce memory request (was 32Gi, exceeds node capacity)"
        )

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
