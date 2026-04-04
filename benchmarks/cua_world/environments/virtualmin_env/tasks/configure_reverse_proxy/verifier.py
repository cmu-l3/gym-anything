#!/usr/bin/env python3
"""
Verifier for configure_reverse_proxy task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_reverse_proxy(traj, env_info, task_info):
    """
    Verify that the reverse proxy was configured correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Modules Enabled (20 pts)
    # Both mod_proxy and mod_proxy_http are required
    if result.get('mod_proxy_enabled') and result.get('mod_proxy_http_enabled'):
        score += 20
        feedback_parts.append("Apache proxy modules enabled")
    elif result.get('mod_proxy_enabled') or result.get('mod_proxy_http_enabled'):
        score += 10
        feedback_parts.append("Apache proxy modules partially enabled")
    else:
        feedback_parts.append("Apache proxy modules NOT enabled")

    # Criterion 2: Config Files Correct (30 pts)
    # Check for presence of directives
    config_score = 0
    if result.get('config_proxypass_found'):
        config_score += 15
    if result.get('config_proxypass_reverse_found'):
        config_score += 15
    
    score += config_score
    if config_score == 30:
        feedback_parts.append("Proxy directives found in config")
    elif config_score > 0:
        feedback_parts.append("Partial proxy directives found")
    else:
        feedback_parts.append("No proxy directives found in config")

    # Criterion 3: End-to-End Functionality (50 pts)
    # This is the most important test - does it actually work?
    if result.get('e2e_test_passed'):
        score += 50
        feedback_parts.append("End-to-end proxy test passed (acmecorp.test/app -> localhost:3001)")
    else:
        feedback_parts.append("End-to-end proxy test FAILED")

    # Anti-gaming check
    # If config was not modified during task, suspicious (unless they did it strictly via runtime CLI which is unlikely for this task)
    if not result.get('config_modified_during_task') and score > 20:
        # If they passed e2e but didn't modify config file, maybe they did it in a way we didn't track?
        # Or maybe the config existed before?
        initial_count = int(result.get('initial_proxy_count', 0))
        if initial_count > 0:
             # Config existed before task, and wasn't modified. Zero score.
             score = 0
             feedback_parts.append("ANTI-GAMING: Proxy config existed before task and was not modified.")
        else:
             # Maybe they used a temp file we didn't find, or runtime config. 
             # We'll allow it if E2E passed, but warn.
             feedback_parts.append("Note: Config file timestamp not updated (did you use a non-standard file?)")

    passed = score >= 75  # Requires E2E + Modules or E2E + Config
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }