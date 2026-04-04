#!/usr/bin/env python3
"""
Verifier for Debug Broken Pipelines task.

Three broken Jenkins pipelines must be diagnosed and fixed:
  - payment-service-ci   : uses 'bat' step (Windows-only) on Linux
  - user-auth-service    : references non-existent credential 'github-deploy-key'
  - inventory-api-build  : missing NEXUS_URL environment variable

Scoring (100 points):
  - payment-service-ci last build is SUCCESS  : 30 pts
  - user-auth-service  last build is SUCCESS  : 30 pts
  - inventory-api-build last build is SUCCESS : 30 pts
  - All three fixed (bonus)                   : 10 pts

Pass threshold: 60 points (2 of 3 pipelines fixed and verified).
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_debug_broken_pipelines(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/debug_broken_pipelines_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result: {e}"}
    except Exception as e:
        logger.error(f"Error reading result: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # ── Criterion 1: payment-service-ci ──────────────────────────────────
    payment = result.get('payment_service_ci', {})
    payment_result = payment.get('result', '')
    payment_new = payment.get('new_build_triggered', False)

    if payment_result == 'SUCCESS' and payment_new:
        score += 30
        subscores['payment_service_ci'] = True
        feedback_parts.append("payment-service-ci: FIXED and passing (30/30)")
    elif payment_result == 'SUCCESS':
        # Build passed but no new build recorded — give credit anyway
        score += 25
        subscores['payment_service_ci'] = 'partial'
        feedback_parts.append("payment-service-ci: passes but could not confirm new build triggered (25/30)")
    else:
        subscores['payment_service_ci'] = False
        feedback_parts.append(
            f"payment-service-ci: still failing (result={payment_result or 'no builds'}) (0/30)")

    # ── Criterion 2: user-auth-service ───────────────────────────────────
    auth = result.get('user_auth_service', {})
    auth_result = auth.get('result', '')
    auth_new = auth.get('new_build_triggered', False)
    cred_created = auth.get('credential_github_deploy_key_created', False)

    if auth_result == 'SUCCESS' and auth_new:
        score += 30
        subscores['user_auth_service'] = True
        feedback_parts.append("user-auth-service: FIXED and passing (30/30)")
    elif auth_result == 'SUCCESS':
        score += 25
        subscores['user_auth_service'] = 'partial'
        feedback_parts.append("user-auth-service: passes but could not confirm new build triggered (25/30)")
    elif cred_created:
        # Credential was created but build not yet re-run
        score += 15
        subscores['user_auth_service'] = 'partial'
        feedback_parts.append(
            "user-auth-service: credential 'github-deploy-key' created but build not yet confirmed passing (15/30)")
    else:
        subscores['user_auth_service'] = False
        feedback_parts.append(
            f"user-auth-service: still failing (result={auth_result or 'no builds'}) (0/30)")

    # ── Criterion 3: inventory-api-build ─────────────────────────────────
    inventory = result.get('inventory_api_build', {})
    inventory_result = inventory.get('result', '')
    inventory_new = inventory.get('new_build_triggered', False)

    if inventory_result == 'SUCCESS' and inventory_new:
        score += 30
        subscores['inventory_api_build'] = True
        feedback_parts.append("inventory-api-build: FIXED and passing (30/30)")
    elif inventory_result == 'SUCCESS':
        score += 25
        subscores['inventory_api_build'] = 'partial'
        feedback_parts.append("inventory-api-build: passes but could not confirm new build triggered (25/30)")
    else:
        subscores['inventory_api_build'] = False
        feedback_parts.append(
            f"inventory-api-build: still failing (result={inventory_result or 'no builds'}) (0/30)")

    # ── Bonus: all three fixed ────────────────────────────────────────────
    all_fixed = (
        subscores.get('payment_service_ci') is True and
        subscores.get('user_auth_service') is True and
        subscores.get('inventory_api_build') is True
    )
    if all_fixed:
        score += 10
        feedback_parts.append("BONUS: All three pipelines fixed and passing (+10)")

    # Cap at 100
    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No pipelines repaired",
        "subscores": subscores
    }
