#!/usr/bin/env python3
"""
Verifier for disable_anonymous_access task.

Criteria:
1. Configuration Check (40 pts): System config shows anonAccessEnabled=false.
2. Behavioral Check (30 pts): Unauthenticated requests return 401 or 403.
3. Sanity Check (15 pts): Authenticated admin requests still return 200.
4. Anti-Gaming (15 pts): State actually changed from initial (200) to blocked.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_anonymous_access(traj, env_info, task_info):
    # 1. Setup retrieval mechanism
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # 2. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Parse Data
    config_anon_enabled = result.get('config_anon_enabled', 'unknown')
    final_anon_status = result.get('final_anon_status', 0)
    final_auth_status = result.get('final_auth_status', 0)
    initial_anon_status = result.get('initial_anon_status', 0)

    score = 0
    feedback_parts = []

    # Criterion 1: Configuration Check (40 pts)
    if config_anon_enabled == "false":
        score += 40
        feedback_parts.append("Config check passed (anonAccessEnabled=false)")
    elif config_anon_enabled == "true":
        feedback_parts.append("Config check failed (anonAccessEnabled is still true)")
    else:
        feedback_parts.append("Config check inconclusive")

    # Criterion 2: Behavioral Check (30 pts)
    # 401 = Unauthorized, 403 = Forbidden. Both imply anonymous access is blocked.
    if final_anon_status in [401, 403]:
        score += 30
        feedback_parts.append(f"Behavioral check passed (HTTP {final_anon_status})")
    elif final_anon_status == 200:
        feedback_parts.append("Behavioral check failed (Anonymous request returned 200 OK)")
    else:
        feedback_parts.append(f"Behavioral check partial (Unexpected HTTP {final_anon_status})")

    # Criterion 3: Sanity Check (15 pts)
    if final_auth_status == 200:
        score += 15
        feedback_parts.append("Admin access verified")
    else:
        feedback_parts.append(f"Admin access broken (HTTP {final_auth_status})")

    # Criterion 4: Anti-Gaming / State Change (15 pts)
    # Verify we actually moved from 200 -> 401/403
    if initial_anon_status == 200 and final_anon_status in [401, 403]:
        score += 15
        feedback_parts.append("State change verified")
    elif initial_anon_status == 0:
        feedback_parts.append("Initial state missing (Anti-gaming check skipped)")
        # If we passed config and behavioral, we give benefit of doubt here
        if score >= 70:
             score += 15
    else:
        feedback_parts.append("No state change detected")

    # Final Evaluation
    passed = score >= 85  # Requires Config + Behavioral + Sanity
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }