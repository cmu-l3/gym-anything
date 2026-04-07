#!/usr/bin/env python3
"""
Verifier for docker_resource_governance task.

Criteria:
1. Resource limits (Memory, CPU) applied correctly to 3 containers.
2. Restart policies applied correctly.
3. acme-worker was stress-tested (evidenced by RestartCount > 0).
4. Documentation created and accurate.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_docker_resource_governance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_containers = metadata.get('containers', {
        "acme-api": {"memory_bytes": 268435456, "nano_cpus": 500000000, "restart_policy": "unless-stopped"},
        "acme-worker": {"memory_bytes": 536870912, "nano_cpus": 1000000000, "restart_policy": "on-failure", "restart_retries": 3},
        "acme-cache": {"memory_bytes": 134217728, "nano_cpus": 250000000, "restart_policy": "always"}
    })

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    actual_containers = result.get('containers', {})

    # Helper to check CPU
    # Docker might report NanoCpus OR CpuQuota/CpuPeriod depending on version/config
    def check_cpu(actual, expected_nano):
        if actual.get('NanoCpus', 0) == expected_nano:
            return True
        # Fallback: check quota/period (default period is usually 100000)
        quota = actual.get('CpuQuota', 0)
        period = actual.get('CpuPeriod', 100000)
        if period > 0 and quota > 0:
            # Expected ratio
            expected_ratio = expected_nano / 1000000000.0
            actual_ratio = quota / period
            return abs(actual_ratio - expected_ratio) < 0.01
        return False

    # 1. Verify Container Configs (75 points total)
    for name, expected in expected_containers.items():
        actual = actual_containers.get(name)
        if not actual:
            feedback.append(f"Container {name} not found or not running.")
            continue
        
        c_score = 0
        
        # Memory (10 pts each)
        if actual.get('Memory') == expected['memory_bytes']:
            c_score += 10
        else:
            feedback.append(f"{name}: Memory {actual.get('Memory')} != {expected['memory_bytes']}")

        # CPU (5 pts each)
        if check_cpu(actual, expected['nano_cpus']):
            c_score += 5
        else:
            feedback.append(f"{name}: CPU incorrect")

        # Restart Policy (5 pts each)
        # For acme-worker we also check max retries
        policy_correct = (actual.get('RestartPolicy') == expected['restart_policy'])
        if name == "acme-worker" and expected.get('restart_retries'):
             if actual.get('RestartRetryCount') != expected['restart_retries']:
                 policy_correct = False
        
        if policy_correct:
            c_score += 5
        else:
            feedback.append(f"{name}: Restart policy {actual.get('RestartPolicy')} != {expected['restart_policy']}")
            
        # Running Status (5 pts total shared, but let's just add check here)
        if actual.get('Status') == 'running':
            c_score += 5
        else:
            feedback.append(f"{name}: Not running")

        score += c_score

    # 2. Verify Stress Test (15 points)
    # acme-worker should have restarted at least once
    worker = actual_containers.get("acme-worker", {})
    restart_count = worker.get("RestartCount", 0)
    oom_killed = worker.get("OOMKilled", False)
    
    if restart_count > 0:
        score += 15
        feedback.append("Stress test verified (worker restarted).")
    elif oom_killed:
         # It was killed but maybe didn't restart yet? still counts as test attempt
        score += 10
        feedback.append("Stress test verified (worker OOM killed).")
    else:
        feedback.append("Stress test NOT verified (acme-worker restart count is 0).")

    # 3. Verify Documentation (10 points)
    doc_exists = result.get('doc_exists', False)
    doc_created = result.get('doc_created_during_task', False)
    doc_content = result.get('doc_content', '').lower()
    
    if doc_exists and doc_created:
        # Check content quality
        if all(k in doc_content for k in ["acme-api", "acme-worker", "acme-cache", "256", "512", "128"]):
            score += 10
            feedback.append("Documentation exists and looks correct.")
        else:
            score += 5
            feedback.append("Documentation exists but missing key details.")
    else:
        feedback.append("Documentation missing or not created during task.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }