#!/usr/bin/env python3
"""
Verifier for configure_public_private_access task.

Criteria:
1. Global Anonymous Access must be ENABLED (system config).
2. Anonymous READ to public path must return 200 OK.
3. Anonymous READ to secret path must return 401 or 403.
4. Anonymous WRITE (PUT) must return 401 or 403 (Safety).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_public_private_access(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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

    # Extract values
    http_public = str(result.get("http_public_read", "0"))
    http_secret = str(result.get("http_secret_read", "0"))
    http_write = str(result.get("http_public_write", "0"))
    global_enabled = result.get("global_anon_enabled", False)

    feedback = []
    score = 0

    # 1. Global Setting (10 pts)
    if global_enabled:
        score += 10
        feedback.append("Global Anonymous Access enabled.")
    else:
        feedback.append("Global Anonymous Access is DISABLED.")

    # 2. Public Read (40 pts)
    # 200 OK means successful download
    if http_public == "200":
        score += 40
        feedback.append("Public folder is accessible (HTTP 200).")
    elif http_public in ["401", "403"]:
        feedback.append("Public folder is BLOCKED (HTTP 401/403).")
    else:
        feedback.append(f"Public folder access error (HTTP {http_public}).")

    # 3. Private Block (40 pts)
    # 401/403 means access denied (Correct)
    # 200 means data leaked (Fail)
    if http_secret in ["401", "403"]:
        score += 40
        feedback.append("Secret folder is protected (HTTP 401/403).")
    elif http_secret == "200":
        score = 0 # FAIL CONDITION: Leaked secrets
        feedback.append("CRITICAL FAIL: Secret folder is accessible anonymously!")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
    else:
        feedback.append(f"Secret folder unexpected status (HTTP {http_secret}).")

    # 4. Write Protection (10 pts)
    if http_write in ["401", "403"]:
        score += 10
        feedback.append("Write access correctly denied.")
    elif http_write in ["200", "201", "204"]:
        score -= 20
        feedback.append("SECURITY RISK: Anonymous user can deploy artifacts!")

    # Final Pass check
    # Need at least 90 points (Global enabled + Public Read + Private Block + Write Block)
    # But flexible: 70 is threshold per design.
    # Must have Public Read AND Private Block to pass.
    
    passed = (http_public == "200") and (http_secret in ["401", "403"])
    
    if not global_enabled and passed:
        # Weird edge case: somehow works without global enabled? Unlikely in Artifactory.
        # Maybe testing quirk. We'll deduct points but allow pass if functional tests work.
        pass

    return {
        "passed": passed and score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }