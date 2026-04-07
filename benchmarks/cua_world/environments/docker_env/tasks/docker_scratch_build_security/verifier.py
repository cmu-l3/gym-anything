#!/usr/bin/env python3
"""
Verifier for docker_scratch_build_security task.
Scores the agent on building a minimal, secure Docker image.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scratch_build(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    max_size_mb = metadata.get('max_size_mb', 20)
    
    # Read result file
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
    feedback = []

    # Criterion 1: Image Created (10 pts)
    if not result.get('image_exists'):
        return {"passed": False, "score": 0, "feedback": "Image payment-validator:secure not found."}
    
    score += 10
    feedback.append("Image created.")

    # Criterion 2: Created During Task (Anti-gaming) (10 pts)
    if result.get('created_during_task'):
        score += 10
    else:
        feedback.append("Image was not rebuilt during the task session.")

    # Criterion 3: Minimal Size (< 20MB) (20 pts)
    size_mb = result.get('image_size_bytes', 99999999) / (1024 * 1024)
    if size_mb < max_size_mb:
        score += 20
        feedback.append(f"Size check passed ({size_mb:.2f}MB).")
    else:
        feedback.append(f"Image too large ({size_mb:.2f}MB > {max_size_mb}MB). likely not FROM scratch.")

    # Criterion 4: Non-root User (20 pts)
    user = result.get('image_user', '')
    # Acceptable if it's not empty, not "0", and not "root"
    if user and user != "0" and user != "root":
        score += 20
        feedback.append(f"User check passed (running as '{user}').")
    else:
        feedback.append(f"Security check failed: Running as root or user not specified (User='{user}').")

    # Criterion 5: No Shell (Implies Scratch/Distroless) (20 pts)
    # result['shell_exists'] should be 0 (False)
    if result.get('shell_exists', 1) == 0:
        score += 20
        feedback.append("Attack surface check passed (no shell found).")
    else:
        feedback.append("Security check failed: /bin/sh exists in the image.")

    # Criterion 6: Functional HTTPS (20 pts)
    if result.get('https_check_passed'):
        score += 20
        feedback.append("Functionality check passed (HTTPS working).")
    else:
        feedback.append("Functionality check failed: App crashed or could not connect to HTTPS (missing certs?).")

    passed = score >= metadata.get('pass_threshold', 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }