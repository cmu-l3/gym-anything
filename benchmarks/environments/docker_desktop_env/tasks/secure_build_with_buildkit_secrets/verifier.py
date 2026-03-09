#!/usr/bin/env python3
"""
Verifier for secure_build_with_buildkit_secrets task.

Scoring Criteria:
1. Build Success (30 pts): Image exists.
2. Artifact Downloaded (30 pts): The proprietary file is inside the image.
3. Security (40 pts):
   - Token NOT in history (20 pts)
   - Token NOT in env vars (20 pts)
   - (Implicitly requires using BuildKit secrets to pass both above while getting the artifact)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_build(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve verification results: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Build Success
    image_exists = result.get("image_exists", False)
    if image_exists:
        score += 30
        feedback_parts.append("Image built successfully (+30)")
    else:
        feedback_parts.append("Image 'secure-app:latest' not found (0)")

    # 2. Artifact Verification
    artifact_found = result.get("artifact_found", False)
    if artifact_found:
        score += 30
        feedback_parts.append("Proprietary library found in image (+30)")
    else:
        if image_exists:
            feedback_parts.append("Library missing from image - download failed? (0)")
        else:
            feedback_parts.append("Library missing (no image) (0)")

    # 3. Security Verification
    leaked_hist = result.get("token_leaked_in_history", True)
    leaked_env = result.get("token_leaked_in_env", True)
    
    # If image doesn't exist, we can't really give security points, 
    # but strictly speaking, they didn't leak it if they didn't build it.
    # However, for this task, you only get security points if you actually built something.
    if image_exists:
        if not leaked_hist:
            score += 20
            feedback_parts.append("Token NOT found in build history (+20)")
        else:
            feedback_parts.append("SECURITY FAIL: Token visible in docker history (-0)")
            
        if not leaked_env:
            score += 20
            feedback_parts.append("Token NOT found in environment variables (+20)")
        else:
            feedback_parts.append("SECURITY FAIL: Token visible in ENV (-0)")
    else:
        feedback_parts.append("No security check performed (no image)")

    # Bonus/Sanity check info (not scored directly, but useful for feedback)
    uses_mount = result.get("dockerfile_uses_secret_mount", False)
    if uses_mount:
        feedback_parts.append("(Detected 'RUN --mount=type=secret' in Dockerfile)")
    else:
        feedback_parts.append("(Did NOT detect 'RUN --mount=type=secret' in Dockerfile)")

    # Pass Condition:
    # Must have image + artifact + NO leaks (Score should be 100)
    passed = (score == 100)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }