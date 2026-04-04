#!/usr/bin/env python3
"""
Verifier for revoke_leaked_access_token task.

SCORING CRITERIA:
1. Leaked Token ('Jenkins-Staging') must be REVOKED (60 points).
   - Verified by attempting to use the token (expecting HTTP 401).
2. Safe Token ('Jenkins-Production') must be ACTIVE (40 points).
   - Verified by attempting to use the token (expecting HTTP 200).
   - This ensures the agent didn't just "delete all tokens".

The actual functional checks are performed inside the container by export_result.sh,
which saves the results to /tmp/task_result.json.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_revoke_leaked_access_token(traj, env_info, task_info):
    """
    Verify that the specific token was revoked while others remain active.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result from container: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: Leaked token revoked (60pts)
    leaked_revoked = result.get("leaked_token_revoked", False)
    staging_code = result.get("staging_http_code", "unknown")
    
    if leaked_revoked:
        score += 60
        feedback_parts.append("Success: 'Jenkins-Staging' token is revoked.")
    else:
        feedback_parts.append(f"Fail: 'Jenkins-Staging' token is still active (HTTP {staging_code}).")

    # Criterion 2: Production token active (40pts)
    prod_active = result.get("production_token_active", False)
    prod_code = result.get("production_http_code", "unknown")
    
    if prod_active:
        score += 40
        feedback_parts.append("Success: 'Jenkins-Production' token remains active.")
    else:
        feedback_parts.append(f"Fail: 'Jenkins-Production' token was incorrectly revoked/broken (HTTP {prod_code}).")

    # Pass/Fail determination
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }