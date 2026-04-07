#!/usr/bin/env python3
"""
Verifier for docker_oom_debugging task.

Scoring Criteria:
1. Container Stability (40 pts): Container is running and not OOMKilled.
2. Configuration Tuning (30 pts): App configured to use <= 250MB.
3. Constraint Respect (30 pts): Docker memory limit (300MB) was NOT increased.

Total: 100 pts. Pass threshold: 70 pts.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_oom_debugging(traj, env_info, task_info):
    """
    Verify the OOM debugging task.
    """
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

    # Extract metrics
    state = result.get('container_state', {})
    file_config = result.get('file_config', {})
    is_stable = result.get('is_stable', False)
    
    score = 0
    feedback = []

    # Criterion 1: Stability (40 pts)
    # Must be running, not OOMKilled recently
    is_running = state.get('running', False)
    exit_code = state.get('exit_code', 0)
    oom_killed = state.get('oom_killed', False)

    if is_stable and is_running and exit_code == 0 and not oom_killed:
        score += 40
        feedback.append("Stability: Container is running stably (40/40)")
    elif is_running:
        # Running but maybe flagged unstable or restart count high?
        # We'll give partial credit if it's currently up
        score += 20
        feedback.append("Stability: Container is running but might be unstable (20/40)")
    else:
        feedback.append(f"Stability: Container is NOT running (Exit Code: {exit_code}, OOM: {oom_killed}) (0/40)")

    # Criterion 2: App Configuration (30 pts)
    # MAX_ALLOCATION_MB should be <= 250 (Safe threshold)
    # We check both the running environment and the file to be sure
    env_alloc = state.get('env_alloc_mb', 9999)
    try:
        file_alloc = int(file_config.get('alloc_mb', 9999))
    except:
        file_alloc = 9999
        
    # Use the lower of the two found values (giving benefit of doubt if parsing failed on one)
    actual_alloc = min(env_alloc, file_alloc) if (env_alloc > 0 and file_alloc > 0) else (env_alloc if env_alloc > 0 else file_alloc)
    
    if actual_alloc <= 250:
        score += 30
        feedback.append(f"Config: App tuned correctly (MAX_ALLOCATION_MB={actual_alloc}) (30/30)")
    elif actual_alloc <= 300:
        # It equals the limit, which is risky (overhead might kill it)
        score += 15
        feedback.append(f"Config: App tuned riskily (MAX_ALLOCATION_MB={actual_alloc}). Leave room for overhead! (15/30)")
    else:
        feedback.append(f"Config: App allocation too high ({actual_alloc}MB > 300MB limit) (0/30)")

    # Criterion 3: Constraint Respect (30 pts)
    # Memory limit must be <= 300MB (314572800 bytes)
    current_limit = state.get('memory_limit', 0)
    # 300 * 1024 * 1024 = 314572800
    MAX_BYTES = 314572800
    
    # 0 means no limit (BAD)
    if current_limit > 0 and current_limit <= MAX_BYTES:
        score += 30
        feedback.append("Constraint: Docker memory limit preserved (30/30)")
    else:
        feedback.append(f"Constraint: Docker memory limit removed or increased! ({current_limit} bytes) (0/30)")

    # Final Pass/Fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }