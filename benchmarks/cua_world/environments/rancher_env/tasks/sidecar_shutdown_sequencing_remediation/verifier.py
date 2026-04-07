#!/usr/bin/env python3
"""
Verifier for sidecar_shutdown_sequencing_remediation task.

Scoring (100 points total, 20 pts per criterion):
- C1: terminationGracePeriodSeconds == 45
- C2: processor preStop command correctly configured
- C3: network-proxy preStop command correctly configured
- C4: processor livenessProbe correctly configured (HTTP GET /, port 80, delay 10, period 10)
- C5: At least 1 pod in Running state (ensures the probe config doesn't instantly crash the pod)

Pass threshold: 80 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_sidecar_shutdown_sequencing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available in env_info"}

    result_path = '/tmp/task_result.json'
    score = 0
    feedback_parts = []

    try:
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp:
            tmp_path = tmp.name

        copy_from_env(result_path, tmp_path)

        with open(tmp_path, 'r') as f:
            result = json.load(f)

        os.unlink(tmp_path)

    except (FileNotFoundError, json.JSONDecodeError, Exception) as e:
        return {
            'passed': False,
            'score': 0,
            'feedback': f"Failed to read result file: {e}"
        }

    deployment = result.get("deployment", {})
    if not deployment or "spec" not in deployment:
        return {"passed": False, "score": 0, "feedback": "Deployment 'payment-processor' not found or invalid"}

    pod_spec = deployment.get("spec", {}).get("template", {}).get("spec", {})
    containers = pod_spec.get("containers", [])
    
    grace_period = pod_spec.get("terminationGracePeriodSeconds")
    processor_container = next((c for c in containers if c.get("name") == "processor"), {})
    proxy_container = next((c for c in containers if c.get("name") == "network-proxy"), {})

    # ── C1: terminationGracePeriodSeconds (20 pts)
    if grace_period == 45:
        score += 20
        feedback_parts.append("C1 PASS: terminationGracePeriodSeconds is 45 (+20)")
    else:
        feedback_parts.append(f"C1 FAIL: terminationGracePeriodSeconds is {grace_period} (expected 45)")

    # ── C2: processor preStop hook (20 pts)
    proc_pre_stop = processor_container.get("lifecycle", {}).get("preStop", {}).get("exec", {}).get("command", [])
    proc_cmd_str = " ".join([str(x) for x in proc_pre_stop])
    
    # We look for core attributes of the command rather than strict array match, because
    # YAML serialization formats might differ slightly (e.g. single vs double quotes)
    if "wget" in proc_cmd_str and "localhost:80/flush" in proc_cmd_str and "sleep 10" in proc_cmd_str:
        score += 20
        feedback_parts.append("C2 PASS: processor preStop command correctly configured (+20)")
    else:
        feedback_parts.append(f"C2 FAIL: processor preStop command is incorrect. Got: {proc_pre_stop}")

    # ── C3: network-proxy preStop hook (20 pts)
    proxy_pre_stop = proxy_container.get("lifecycle", {}).get("preStop", {}).get("exec", {}).get("command", [])
    proxy_cmd_str = " ".join([str(x) for x in proxy_pre_stop])
    
    if "sleep 20" in proxy_cmd_str:
        score += 20
        feedback_parts.append("C3 PASS: network-proxy preStop command correctly configured (+20)")
    else:
        feedback_parts.append(f"C3 FAIL: network-proxy preStop command is incorrect. Got: {proxy_pre_stop}")

    # ── C4: processor livenessProbe (20 pts)
    liveness = processor_container.get("livenessProbe", {})
    http_get = liveness.get("httpGet", {})
    initial_delay = liveness.get("initialDelaySeconds")
    period = liveness.get("periodSeconds")
    
    # Port can be represented as int 80 or string "80" or named port "http"
    port_correct = str(http_get.get("port", "")) in ["80", "http"]
    path_correct = http_get.get("path") == "/"
    delay_correct = initial_delay == 10
    period_correct = period == 10

    if port_correct and path_correct and delay_correct and period_correct:
        score += 20
        feedback_parts.append("C4 PASS: processor livenessProbe matches spec (+20)")
    else:
        feedback_parts.append(f"C4 FAIL: processor livenessProbe incorrect (port={http_get.get('port')}, path={http_get.get('path')}, delay={initial_delay}, period={period})")

    # ── C5: Pods running (20 pts)
    pods_running = int(result.get("pods_running", 0))
    if pods_running >= 1:
        score += 20
        feedback_parts.append(f"C5 PASS: {pods_running} payment-processor pod(s) running (+20)")
    else:
        feedback_parts.append("C5 FAIL: No payment-processor pods are in Running state. (Did the liveness probe fail due to misconfiguration?)")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }