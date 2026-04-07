#!/usr/bin/env python3
"""
Verifier for pod_lifecycle_governance task.

Scoring (100 points total, 25 each):
- C1: public-api 'api-container' has a preStop exec hook running `["/bin/sleep", "15"]`
- C2: report-generator pod template has annotation `cluster-autoscaler.kubernetes.io/safe-to-evict: "false"`
- C3: cache-node pod spec has `terminationGracePeriodSeconds` = 120
- C4: cache-node 'redis' container has a preStop exec hook running `["redis-cli", "save"]`

*CRITICAL*: To earn points for any criterion, the corresponding deployment must have at least 1 pod 
in the `Running` phase. This ensures agents don't receive points for invalid YAML that breaks the deployment.

Pass threshold: 75 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/pod_lifecycle_governance_result.json"
PASS_THRESHOLD = 75


def verify_pod_lifecycle_governance(traj, env_info, task_info):
    """Verify that all lifecycle configurations were applied correctly to the Deployments."""
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

    deps = result.get("deployments", {}).get("items", [])
    running_pods = result.get("running_pods", {})

    dep_map = {d.get("metadata", {}).get("name"): d for d in deps}
    score = 0
    feedback_parts = []

    # ── Helper to safely extract container commands ──
    def get_prestop_command(deployment, container_name):
        try:
            containers = deployment["spec"]["template"]["spec"]["containers"]
            for c in containers:
                if c.get("name") == container_name:
                    return c.get("lifecycle", {}).get("preStop", {}).get("exec", {}).get("command")
        except KeyError:
            pass
        return None

    # ── Criterion 1: public-api preStop hook ──────────────────────────────────
    pub_api = dep_map.get("public-api")
    pub_api_running = int(running_pods.get("public-api", 0))

    if pub_api and pub_api_running >= 1:
        cmd = get_prestop_command(pub_api, "api-container")
        if cmd == ["/bin/sleep", "15"]:
            score += 25
            feedback_parts.append("C1 PASS: public-api has correct preStop hook (+25)")
        else:
            feedback_parts.append(f"C1 FAIL: public-api preStop hook is '{cmd}', expected '[\"/bin/sleep\", \"15\"]'")
    else:
        feedback_parts.append("C1 FAIL: public-api deployment is missing or has no Running pods (YAML syntax error?)")

    # ── Criterion 2: report-generator annotation ──────────────────────────────
    rep_gen = dep_map.get("report-generator")
    rep_gen_running = int(running_pods.get("report-generator", 0))

    if rep_gen and rep_gen_running >= 1:
        try:
            pod_annotations = rep_gen["spec"]["template"]["metadata"].get("annotations", {})
        except KeyError:
            pod_annotations = {}
        
        try:
            dep_annotations = rep_gen["metadata"].get("annotations", {})
        except KeyError:
            dep_annotations = {}

        if pod_annotations.get("cluster-autoscaler.kubernetes.io/safe-to-evict") == "false":
            score += 25
            feedback_parts.append("C2 PASS: report-generator Pod template has correct eviction annotation (+25)")
        elif dep_annotations.get("cluster-autoscaler.kubernetes.io/safe-to-evict") == "false":
            feedback_parts.append("C2 FAIL: Annotation was applied to Deployment metadata instead of the Pod template")
        else:
            feedback_parts.append("C2 FAIL: report-generator missing the safe-to-evict annotation on Pod template")
    else:
        feedback_parts.append("C2 FAIL: report-generator deployment is missing or has no Running pods")

    # ── Criteria 3 & 4: cache-node grace period and preStop hook ──────────────
    cache = dep_map.get("cache-node")
    cache_running = int(running_pods.get("cache-node", 0))

    if cache and cache_running >= 1:
        # C3: Grace period
        try:
            tgps = cache["spec"]["template"]["spec"].get("terminationGracePeriodSeconds")
        except KeyError:
            tgps = None

        if tgps == 120:
            score += 25
            feedback_parts.append("C3 PASS: cache-node terminationGracePeriodSeconds is 120 (+25)")
        else:
            feedback_parts.append(f"C3 FAIL: cache-node terminationGracePeriodSeconds is {tgps}, expected 120")

        # C4: preStop hook
        cmd = get_prestop_command(cache, "redis")
        if cmd == ["redis-cli", "save"]:
            score += 25
            feedback_parts.append("C4 PASS: cache-node has correct preStop hook (+25)")
        else:
            feedback_parts.append(f"C4 FAIL: cache-node preStop hook is '{cmd}', expected '[\"redis-cli\", \"save\"]'")
    else:
        feedback_parts.append("C3 & C4 FAIL: cache-node deployment is missing or has no Running pods")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }