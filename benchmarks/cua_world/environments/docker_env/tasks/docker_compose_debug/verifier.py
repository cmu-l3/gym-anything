#!/usr/bin/env python3
"""
Verifier for docker_compose_debug task.

Scoring (100 points):
  - acme-db running and healthy: 15 pts
  - acme-cache running and healthy: 10 pts
  - acme-api running and healthy: 20 pts
  - acme-nginx running: 15 pts
  - acme-worker running: 15 pts
  - API responds 200 via nginx with product data: 25 pts

Pass threshold: 65 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65


def verify_docker_compose_debug(traj, env_info, task_info):
    """Verify that all 5 services are running and API responds through nginx."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/docker_compose_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # ── Criterion 1: Database running and healthy (15 pts) ───────────────────
    db_running = result.get("db_running", 0)
    db_healthy = result.get("db_healthy", 0)

    if db_running and db_healthy:
        score += 15
        subscores["db"] = True
        feedback_parts.append("acme-db: running and healthy (+15)")
    elif db_running:
        score += 8
        subscores["db"] = "partial"
        feedback_parts.append("acme-db: running but not healthy (8/15)")
    else:
        subscores["db"] = False
        feedback_parts.append("acme-db: not running (0/15)")

    # ── Criterion 2: Cache running and healthy (10 pts) ──────────────────────
    cache_running = result.get("cache_running", 0)
    cache_healthy = result.get("cache_healthy", 0)

    if cache_running and cache_healthy:
        score += 10
        subscores["cache"] = True
        feedback_parts.append("acme-cache: running and healthy (+10)")
    elif cache_running:
        score += 5
        subscores["cache"] = "partial"
        feedback_parts.append("acme-cache: running but not healthy (5/10)")
    else:
        subscores["cache"] = False
        feedback_parts.append("acme-cache: not running (0/10)")

    # ── Criterion 3: API running and healthy (20 pts) ────────────────────────
    api_running = result.get("api_running", 0)
    api_healthy = result.get("api_healthy", 0)

    if api_running and api_healthy:
        score += 20
        subscores["api"] = True
        feedback_parts.append("acme-api: running and healthy (+20)")
    elif api_running:
        score += 10
        subscores["api"] = "partial"
        feedback_parts.append("acme-api: running but not healthy (10/20)")
    else:
        subscores["api"] = False
        feedback_parts.append("acme-api: not running (0/20)")

    # ── Criterion 4: Nginx running (15 pts) ──────────────────────────────────
    nginx_running = result.get("nginx_running", 0)

    if nginx_running:
        score += 15
        subscores["nginx"] = True
        feedback_parts.append("acme-nginx: running (+15)")
    else:
        subscores["nginx"] = False
        feedback_parts.append("acme-nginx: not running (0/15)")

    # ── Criterion 5: Worker running (15 pts) ─────────────────────────────────
    worker_running = result.get("worker_running", 0)

    if worker_running:
        score += 15
        subscores["worker"] = True
        feedback_parts.append("acme-worker: running (+15)")
    else:
        subscores["worker"] = False
        feedback_parts.append("acme-worker: not running (0/15)")

    # ── Criterion 6: API responds via nginx (25 pts) ─────────────────────────
    api_responds = result.get("api_responds", 0)
    has_products = result.get("has_products_json", 0)
    api_code = result.get("api_status_code", "000")

    if api_responds and has_products:
        score += 25
        subscores["api_via_nginx"] = True
        feedback_parts.append("API responds 200 via nginx with product data (+25)")
    elif api_responds:
        score += 15
        subscores["api_via_nginx"] = "partial"
        feedback_parts.append(f"API responds via nginx (HTTP {api_code}) but response missing product data (15/25)")
    else:
        subscores["api_via_nginx"] = False
        feedback_parts.append(f"API does not respond via nginx (HTTP {api_code}) (0/25)")

    # ── Score cap: API via nginx requires API service to be running ───────────
    if not api_running and subscores.get("api_via_nginx") not in (False,):
        pass  # if api somehow responds without container, trust the curl result

    # ── GATE: Must have API responding to pass ────────────────────────────────
    if not api_responds and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(
            f"Score capped at {PASS_THRESHOLD - 1}: end-to-end API response is required to pass"
        )

    passed = score >= PASS_THRESHOLD

    # Include bug fix status in details
    bug_fixes = {
        "bug1_postgres_db_name": bool(result.get("bug1_fixed_postgres_db")),
        "bug2_network_name": bool(result.get("bug2_fixed_network")),
        "bug3_redis_url_scheme": bool(result.get("bug3_fixed_redis_url")),
        "bug4_nginx_upstream_port": bool(result.get("bug4_fixed_nginx_port")),
        "bug5_worker_module_path": bool(result.get("bug5_fixed_worker_cmd")),
    }
    bugs_fixed_count = sum(bug_fixes.values())
    feedback_parts.append(f"Config bugs fixed: {bugs_fixed_count}/5")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "bug_fixes": bug_fixes,
    }
