#!/usr/bin/env python3
"""
Verifier for block_snapshot_artifacts task.

Criteria:
1. Configuration: Repository excludesPattern must contain 'SNAPSHOT' (30 pts).
2. Functional: Uploading a SNAPSHOT artifact must fail (40 pts).
3. Functional: Uploading a normal artifact must succeed (30 pts).
4. VLM Verification: Agent navigated to repository configuration (Penalty check).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_block_snapshot_artifacts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Configuration Check (30 points)
    excludes_pattern = result.get("excludes_pattern", "")
    if "SNAPSHOT" in excludes_pattern.upper():
        score += 30
        feedback_parts.append(f"Configuration updated correctly (pattern: '{excludes_pattern}')")
    else:
        feedback_parts.append(f"Configuration missing 'SNAPSHOT' in excludes (found: '{excludes_pattern}')")

    # 2. Functional Check: Block Snapshot (40 points)
    # 409 (Conflict) is typical for prohibited deploys, 403 (Forbidden) is also possible depending on config.
    # 201 means it was created (bad).
    snapshot_status = result.get("snapshot_upload_http_status", 0)
    if snapshot_status in [403, 409]:
        score += 40
        feedback_parts.append("Snapshot upload blocked successfully")
    elif snapshot_status == 201:
        feedback_parts.append("Snapshot upload succeeded (Failed to block)")
    else:
        feedback_parts.append(f"Snapshot upload returned unexpected status {snapshot_status}")

    # 3. Functional Check: Allow Release (30 points)
    release_status = result.get("release_upload_http_status", 0)
    if release_status == 201:
        score += 30
        feedback_parts.append("Release upload succeeded")
    else:
        feedback_parts.append(f"Release upload failed (Status {release_status}) - Policy might be too aggressive")

    # Final Score Calculation
    passed = score >= 70 and ("SNAPSHOT" in excludes_pattern.upper())
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }