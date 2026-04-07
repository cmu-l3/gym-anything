#!/usr/bin/env python3
"""
Verifier for docker_secure_build_secrets task.

Scoring (100 points):
  - Secure History (Token NOT in history): 40 pts
  - Build Success (Image exists + lockfile): 20 pts
  - Dockerfile Implementation (uses --mount): 15 pts
  - Script Implementation (reads /run/secrets): 15 pts
  - Build Script (uses --secret): 10 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_secure_build_secrets(traj, env_info, task_info):
    """Verify that the Docker build uses secrets securely."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/task_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # Extract data
    image_exists = result.get("image_exists", 0)
    history_leak = result.get("history_leak", 1) # Default to 1 (leak) if missing
    build_success = result.get("build_success", 0)
    
    dockerfile_uses_mount = result.get("dockerfile_uses_mount", 0)
    script_reads_secret = result.get("script_reads_secret", 0)
    build_script_uses_secret = result.get("build_script_uses_secret", 0)

    # Criterion 1: Secure History (40 pts)
    # This implies image must exist AND no leak found
    if image_exists and not history_leak:
        score += 40
        feedback_parts.append("History Secure: Token not found in image layers (+40)")
    elif image_exists and history_leak:
        feedback_parts.append("SECURITY FAIL: Token string found in docker history (0/40)")
    else:
        feedback_parts.append("Image not found (0/40)")

    # Criterion 2: Build Functionality (20 pts)
    # The image must actually work (lockfile present means script succeeded with correct token)
    if build_success:
        score += 20
        feedback_parts.append("Build Success: Dependency lockfile found (+20)")
    elif image_exists:
        feedback_parts.append("Build Broken: Dependency lockfile missing - install script likely failed (0/20)")
    else:
        pass # Already noted

    # Criterion 3: Dockerfile Syntax (15 pts)
    if dockerfile_uses_mount:
        score += 15
        feedback_parts.append("Dockerfile: Uses --mount=type=secret (+15)")
    else:
        feedback_parts.append("Dockerfile: Missing --mount=type=secret syntax (0/15)")

    # Criterion 4: Script Implementation (15 pts)
    if script_reads_secret:
        score += 15
        feedback_parts.append("Install Script: Reads from /run/secrets (+15)")
    else:
        feedback_parts.append("Install Script: Does not appear to read /run/secrets (0/15)")

    # Criterion 5: Build Script (10 pts)
    if build_script_uses_secret:
        score += 10
        feedback_parts.append("Build Script: Uses --secret flag (+10)")
    else:
        feedback_parts.append("Build Script: Missing --secret flag (0/10)")

    # Final Verification
    passed = score >= PASS_THRESHOLD and not history_leak and build_success

    if history_leak:
        # Critical failure regardless of other points
        passed = False
        feedback_parts.insert(0, "[CRITICAL] Security leak detected.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }