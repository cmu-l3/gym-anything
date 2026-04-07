#!/usr/bin/env python3
"""
Verifier for kustomize_overlay_remediation task.

Verification Criteria (100 points total):
- C1 (20 pts): Resources exist in `payment-staging` with `environment: staging` label.
- C2 (20 pts): Deployment uses image `nginx:1.24-alpine`.
- C3 (20 pts): Deployment configured for 3 replicas.
- C4 (20 pts): ConfigMap `LOG_LEVEL` patched to `DEBUG`.
- C5 (20 pts): Local files fixed (kustomize build returns exit code 0).

Pass Threshold: 80 points, but C5 MUST be met (Agent cannot bypass Kustomize).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/kustomize_overlay_result.json"
PASS_THRESHOLD = 80

def verify_kustomize_overlay_remediation(traj, env_info, task_info):
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
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
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

    # ── Extract Data ─────────────────────────────────────────────────────────
    ns_exists = result.get("namespace_exists", False)
    deployment = result.get("deployment", {})
    service = result.get("service", {})
    configmap = result.get("configmap", {})
    kustomize_exit_code = result.get("kustomize_exit_code", -1)

    # ── C1: Namespace and Labels (20 pts) ────────────────────────────────────
    deploy_env_label = deployment.get("metadata", {}).get("labels", {}).get("environment", "")
    svc_env_label = service.get("metadata", {}).get("labels", {}).get("environment", "")
    cm_env_label = configmap.get("metadata", {}).get("labels", {}).get("environment", "")
    
    c1_met = (
        ns_exists and 
        deploy_env_label == "staging" and 
        svc_env_label == "staging" and 
        cm_env_label == "staging"
    )
    
    if c1_met:
        score += 20
        feedback_parts.append("PASS C1: Namespace exists and resources labeled properly (+20)")
    else:
        feedback_parts.append(
            f"FAIL C1: Missing namespace or labels (Deploy={deploy_env_label}, Svc={svc_env_label}, CM={cm_env_label})"
        )

    # ── C2: Image Verification (20 pts) ──────────────────────────────────────
    containers = deployment.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])
    image = containers[0].get("image", "") if containers else ""
    
    c2_met = image == "nginx:1.24-alpine"
    if c2_met:
        score += 20
        feedback_parts.append("PASS C2: Deployment uses correct image (+20)")
    else:
        feedback_parts.append(f"FAIL C2: Image is '{image}' (expected 'nginx:1.24-alpine')")

    # ── C3: Replicas Verification (20 pts) ───────────────────────────────────
    replicas = deployment.get("spec", {}).get("replicas", -1)
    
    c3_met = replicas == 3
    if c3_met:
        score += 20
        feedback_parts.append("PASS C3: Deployment scaled to 3 replicas (+20)")
    else:
        feedback_parts.append(f"FAIL C3: Deployment has {replicas} replicas (expected 3)")

    # ── C4: ConfigMap Data Verification (20 pts) ─────────────────────────────
    log_level = configmap.get("data", {}).get("LOG_LEVEL", "")
    
    c4_met = log_level == "DEBUG"
    if c4_met:
        score += 20
        feedback_parts.append("PASS C4: ConfigMap LOG_LEVEL successfully patched to DEBUG (+20)")
    else:
        feedback_parts.append(f"FAIL C4: ConfigMap LOG_LEVEL is '{log_level}' (expected 'DEBUG')")

    # ── C5: Kustomize Static Build (20 pts - Anti-Gaming) ────────────────────
    c5_met = kustomize_exit_code == 0
    if c5_met:
        score += 20
        feedback_parts.append("PASS C5: Kustomize overlay builds successfully without syntax errors (+20)")
    else:
        feedback_parts.append(
            f"FAIL C5: 'kubectl kustomize' fails on local files (Exit code {kustomize_exit_code}). Declarative files remain broken!"
        )

    # Agent must meet the score threshold AND fix the files (C5 required)
    passed = score >= PASS_THRESHOLD and c5_met

    if score >= PASS_THRESHOLD and not c5_met:
        feedback_parts.append("CRITICAL FAIL: Score met threshold, but Kustomize files were not fixed (failed C5).")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }