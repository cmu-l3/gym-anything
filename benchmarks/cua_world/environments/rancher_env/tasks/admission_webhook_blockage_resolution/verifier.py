#!/usr/bin/env python3
"""
Verifier for admission_webhook_blockage_resolution task.

Scoring (100 points total, Pass threshold: 70):
- C1 (30 pts): security-policy-validator VWC is resolved
- C2 (30 pts): resource-defaults-injector MWC is resolved
- C3 (25 pts): webhook-test deployment is successfully running in staging
- C4 (15 pts): nginx-web deployment (existing workload) is intact and running

Definition of "Resolved":
  A webhook is resolved if it meets ANY of the following:
  1. The webhook configuration is deleted.
  2. The webhook's failurePolicy is changed to "Ignore".
  3. The staging namespace no longer has labels that match the webhook's namespaceSelector.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/admission_webhook_blockage_resolution_result.json"
PASS_THRESHOLD = 70


def is_webhook_resolved(webhook_json, staging_ns_json):
    """
    Evaluates whether a given webhook configuration is no longer blocking the staging namespace.
    """
    # 1. Check if it was deleted
    if not webhook_json or "webhooks" not in webhook_json:
        return True, "Webhook configuration deleted"

    # Get staging labels to evaluate namespace selector
    staging_labels = staging_ns_json.get("metadata", {}).get("labels", {})

    webhooks = webhook_json.get("webhooks", [])
    if not webhooks:
        return True, "Webhook configuration has no webhooks"

    for wh in webhooks:
        # 2. Check if failurePolicy is Ignore
        if wh.get("failurePolicy") == "Ignore":
            continue  # This specific hook is safe, check others

        # 3. Check if namespaceSelector matches staging labels
        selector = wh.get("namespaceSelector", {})
        match_labels = selector.get("matchLabels", {})
        
        # If there are matchLabels, evaluate them against staging_labels
        matches = True
        if match_labels:
            for k, v in match_labels.items():
                if staging_labels.get(k) != v:
                    matches = False
                    break
        else:
            # If matchLabels is completely empty, it matches ALL namespaces.
            # But in our setup it explicitly matched webhook-enforce="true".
            # If they removed the matchLabels entirely, it matches all namespaces
            # and failurePolicy is still Fail -> it blocks everything (including staging)
            matches = True 
            
        if not matches:
            continue  # Does not target staging, so it's safe

        # If we reach here, failurePolicy is Fail AND it matches the staging namespace
        return False, f"Webhook '{wh.get('name')}' is still blocking (failurePolicy: Fail, matches staging labels)"

    return True, "Webhook configuration is safely bypassed or ignored"


def get_running_pods(pods_json):
    """Returns the number of pods in the Running phase."""
    count = 0
    for pod in pods_json.get("items", []):
        if pod.get("status", {}).get("phase") == "Running":
            count += 1
    return count


def verify_admission_webhook_blockage(traj, env_info, task_info):
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

    vwc = result.get("vwc_security_policy", {})
    mwc = result.get("mwc_resource_injector", {})
    staging = result.get("staging_namespace", {})
    
    # ── C1: Validating Webhook Resolved (30 pts) ────────────────────────────
    c1_resolved, c1_reason = is_webhook_resolved(vwc, staging)
    if c1_resolved:
        score += 30
        feedback_parts.append(f"C1 PASS: security-policy-validator resolved ({c1_reason}) [+30]")
    else:
        feedback_parts.append(f"C1 FAIL: security-policy-validator not resolved ({c1_reason})")

    # ── C2: Mutating Webhook Resolved (30 pts) ──────────────────────────────
    c2_resolved, c2_reason = is_webhook_resolved(mwc, staging)
    if c2_resolved:
        score += 30
        feedback_parts.append(f"C2 PASS: resource-defaults-injector resolved ({c2_reason}) [+30]")
    else:
        feedback_parts.append(f"C2 FAIL: resource-defaults-injector not resolved ({c2_reason})")

    # ── C3: Test Deployment Running (25 pts) ────────────────────────────────
    test_deploy = result.get("test_deployment", {})
    test_pods = result.get("test_pods", {})
    
    test_exists = bool(test_deploy and test_deploy.get("metadata", {}).get("name"))
    test_running = get_running_pods(test_pods)
    
    if test_exists and test_running >= 1:
        score += 25
        feedback_parts.append(f"C3 PASS: webhook-test deployment successfully created and running ({test_running} pods) [+25]")
    else:
        if test_exists:
            feedback_parts.append(f"C3 FAIL: webhook-test deployment exists but has {test_running} running pods (expected >= 1)")
        else:
            feedback_parts.append("C3 FAIL: webhook-test deployment was not created in the staging namespace")

    # ── C4: Existing Workload Intact (15 pts) ───────────────────────────────
    nginx_deploy = result.get("nginx_deployment", {})
    nginx_pods = result.get("nginx_pods", {})
    
    nginx_exists = bool(nginx_deploy and nginx_deploy.get("metadata", {}).get("name"))
    nginx_running = get_running_pods(nginx_pods)
    
    if nginx_exists and nginx_running >= 1:
        score += 15
        feedback_parts.append(f"C4 PASS: Existing nginx-web deployment is intact ({nginx_running} running pods) [+15]")
    else:
        feedback_parts.append("C4 FAIL: Existing nginx-web workload was deleted or degraded during remediation")

    passed = score >= PASS_THRESHOLD
    
    # Final sanity check: if test deployment works, blockages must have been lifted.
    # We still grade strictly by component, but passing the threshold means they successfully unblocked.
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }