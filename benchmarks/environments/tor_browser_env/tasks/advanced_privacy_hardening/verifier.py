#!/usr/bin/env python3
"""Verifier for advanced_privacy_hardening task.

A privacy engineer must implement 6 specific hardening measures on Tor Browser
for a high-risk journalist client. Verifies all 6 criteria with partial scoring.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "advanced_privacy_hardening"


def verify_advanced_privacy_hardening(traj, env_info, task_info):
    """
    Verify the agent applied all 6 privacy hardening measures.

    Scoring (100 points total):
    1. Security level = Safest (slider=4)     - 20 pts  [REQUIRED for pass]
    2. HTTPS-Only Mode enabled                - 20 pts
    3. network.prefetch-next = false          - 15 pts
    4. browser.sessionstore.privacy_level = 2 - 15 pts
    5. network.http.speculative-parallel-limit = 0 - 15 pts
    6. History never saved                    - 15 pts

    Pass threshold: 60+ points (must include criterion 1 = Safest security level)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env(f"/tmp/{TASK_NAME}_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Result: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []

    # Gate: prefs file must exist (Tor Browser must have been opened)
    if not result.get('prefs_file_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Tor Browser prefs.js not found — browser was not used"
        }

    # Criterion 1: Security level = Safest (slider=4) — REQUIRED for pass
    slider = result.get('security_slider', 1)
    security_level = result.get('security_level', 'standard')
    if slider == 4 and security_level == 'safest':
        score += 20
        feedback_parts.append("Security level = Safest (20/20)")
    elif slider == 2:
        score += 10
        feedback_parts.append("Security level = Safer (partial: 10/20) — need Safest")
    else:
        feedback_parts.append(f"Security level = {security_level} (0/20) — need Safest")

    # Criterion 2: HTTPS-Only Mode enabled
    if result.get('https_only_enabled', False):
        score += 20
        feedback_parts.append("HTTPS-Only Mode enabled (20/20)")
    else:
        feedback_parts.append("HTTPS-Only Mode NOT enabled (0/20)")

    # Criterion 3: network.prefetch-next = false
    if result.get('prefetch_disabled', False):
        score += 15
        feedback_parts.append("network.prefetch-next = false (15/15)")
    else:
        feedback_parts.append("network.prefetch-next NOT disabled (0/15)")

    # Criterion 4: browser.sessionstore.privacy_level = 2
    ss_level = result.get('sessionstore_privacy_level', -1)
    if ss_level == 2:
        score += 15
        feedback_parts.append("browser.sessionstore.privacy_level = 2 (15/15)")
    elif ss_level == 1:
        score += 7
        feedback_parts.append(f"browser.sessionstore.privacy_level = 1 (partial: 7/15) — need 2")
    else:
        feedback_parts.append(f"browser.sessionstore.privacy_level = {ss_level} (0/15) — need 2")

    # Criterion 5: network.http.speculative-parallel-limit = 0
    spec_limit = result.get('speculative_parallel_limit', -1)
    if spec_limit == 0:
        score += 15
        feedback_parts.append("network.http.speculative-parallel-limit = 0 (15/15)")
    else:
        feedback_parts.append(f"network.http.speculative-parallel-limit = {spec_limit} (0/15) — need 0")

    # Criterion 6: History never saved
    if result.get('history_never_saved', False):
        score += 15
        feedback_parts.append("History never saved (15/15)")
    else:
        feedback_parts.append("History saving NOT disabled (0/15)")

    # Pass requires: score >= 60 AND security level = Safest
    security_ok = (slider == 4)
    passed = score >= 60 and security_ok

    feedback = " | ".join(feedback_parts)

    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "subscores": {
            "security_safest": 20 if (slider == 4) else (10 if slider == 2 else 0),
            "https_only": 20 if result.get('https_only_enabled') else 0,
            "prefetch_disabled": 15 if result.get('prefetch_disabled') else 0,
            "sessionstore_level": 15 if ss_level == 2 else (7 if ss_level == 1 else 0),
            "speculative_limit": 15 if spec_limit == 0 else 0,
            "history_disabled": 15 if result.get('history_never_saved') else 0,
        }
    }
