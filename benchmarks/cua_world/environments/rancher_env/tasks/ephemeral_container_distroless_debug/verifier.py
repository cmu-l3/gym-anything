#!/usr/bin/env python3
"""
Verifier for ephemeral_container_distroless_debug task.

Scoring (100 points total, Pass Threshold: 75):
- C1 (25 pts): Pod Preserved (Initial UID == Current UID) - Agent didn't delete the pod
- C2 (25 pts): Ephemeral Container Attached - Agent used the correct debugging mechanism
- C3 (25 pts): Target Secret Exists with 'signature' key
- C4 (25 pts): Extracted Signature precisely matches the randomly generated Ground Truth

Anti-gaming:
- The signature is a random UUID generated at runtime, making guessing impossible.
- Recreating the pod via `kubectl replace` or `kubectl debug --copy-to` changes the UID, failing C1.
- Standard `kubectl exec` / `cp` fails due to stripped binaries in the container setup.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/ephemeral_debug_result.json"
PASS_THRESHOLD = 75


def verify_ephemeral_container_debug(traj, env_info, task_info):
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

    # Parse state
    initial_uid = result.get("initial_pod_uid", "missing")
    current_uid = result.get("current_pod_uid", "not-found")
    ephemeral_count = int(result.get("ephemeral_container_count", 0))
    secret_exists = result.get("secret_exists", False)
    has_sig_key = result.get("has_signature_key", False)
    extracted_signature = str(result.get("extracted_signature", "")).strip()
    ground_truth = str(result.get("ground_truth_signature", "missing")).strip()

    # ── C1: Pod Preserved (UID matches) ───────────────────────────────────────
    c1_pass = (initial_uid == current_uid) and (current_uid not in ["missing", "not-found"])
    if c1_pass:
        score += 25
        feedback_parts.append("C1 PASS: Pod preserved without recreation (+25)")
    else:
        feedback_parts.append(f"C1 FAIL: Pod UID changed or pod deleted (Initial: {initial_uid}, Current: {current_uid})")

    # ── C2: Ephemeral Container Attached ──────────────────────────────────────
    c2_pass = ephemeral_count >= 1
    if c2_pass:
        score += 25
        feedback_parts.append(f"C2 PASS: {ephemeral_count} Ephemeral Container(s) attached to pod (+25)")
    else:
        feedback_parts.append("C2 FAIL: No Ephemeral Containers found on pod specification")

    # ── C3: Target Secret Exists ──────────────────────────────────────────────
    c3_pass = secret_exists and has_sig_key
    if c3_pass:
        score += 25
        feedback_parts.append("C3 PASS: Secret 'fault-signature-hotfix' exists with 'signature' key (+25)")
    else:
        if not secret_exists:
            feedback_parts.append("C3 FAIL: Target secret 'fault-signature-hotfix' not found in namespace")
        else:
            feedback_parts.append("C3 FAIL: Secret exists but missing 'signature' key")

    # ── C4: Signature Matches Ground Truth ────────────────────────────────────
    c4_pass = (extracted_signature == ground_truth) and (ground_truth != "missing")
    if c4_pass:
        score += 25
        feedback_parts.append("C4 PASS: Extracted signature precisely matches ground truth (+25)")
    else:
        feedback_parts.append(f"C4 FAIL: Extracted signature does not match expected value (Got: '{extracted_signature}')")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }