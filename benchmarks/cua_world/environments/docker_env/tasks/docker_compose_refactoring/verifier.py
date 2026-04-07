#!/usr/bin/env python3
"""
Verifier for docker_compose_refactoring task.

Scoring (100 points):
  - Stack running (20 pts): All 4 services are up
  - Base file created (20 pts): docker-compose.base.yml exists
  - 'extends' used (30 pts): Main compose file uses extends keyword
  - Drift fixed (15 pts): transcoder-h264 has restart: always
  - Config integrity (15 pts): Memory limits preserved in running container

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_docker_compose_refactoring(traj, env_info, task_info):
    """Verify Docker Compose refactoring and drift fix."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/refactoring_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Check if stack is running (20 pts)
    all_running = result.get("all_services_running", 0)
    config_valid = result.get("config_valid", 0)
    
    if all_running:
        score += 20
        feedback_parts.append("Stack running (+20)")
    elif config_valid:
        score += 10
        feedback_parts.append("Config valid but services not all running (10/20)")
    else:
        feedback_parts.append("Stack failed to start (0/20)")

    # 2. Check for base file (20 pts)
    base_exists = result.get("base_file_exists", 0)
    if base_exists:
        score += 20
        feedback_parts.append("Base file created (+20)")
    else:
        feedback_parts.append("Base file missing (0/20)")

    # 3. Check for extends usage and line reduction (30 pts)
    uses_extends = result.get("uses_extends", 0)
    initial_lines = result.get("initial_lines", 100)
    final_lines = result.get("final_lines", 100)
    
    # Calculate reduction percentage
    if initial_lines > 0:
        reduction_pct = (initial_lines - final_lines) / initial_lines
    else:
        reduction_pct = 0
        
    if uses_extends:
        if reduction_pct > 0.3: # Expect at least 30% reduction
            score += 30
            feedback_parts.append(f"'extends' used & lines reduced by {int(reduction_pct*100)}% (+30)")
        else:
            score += 20
            feedback_parts.append("'extends' used but line reduction minimal (20/30)")
    else:
        feedback_parts.append("'extends' keyword not found in docker-compose.yml (0/30)")

    # 4. Check Drift Fix (15 pts)
    h264_policy = result.get("h264_restart_policy", "")
    if h264_policy == "always":
        score += 15
        feedback_parts.append("Drift fixed: restart policy is 'always' (+15)")
    else:
        feedback_parts.append(f"Drift NOT fixed: restart policy is '{h264_policy}' (0/15)")

    # 5. Check Config Integrity (15 pts)
    preserved = result.get("config_preserved", 0)
    if preserved:
        score += 15
        feedback_parts.append("Config integrity check passed (+15)")
    else:
        feedback_parts.append("Config integrity check failed (resource limits lost?) (0/15)")

    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }