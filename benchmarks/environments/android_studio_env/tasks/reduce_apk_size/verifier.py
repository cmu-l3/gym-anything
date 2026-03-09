#!/usr/bin/env python3
"""
Verifier for reduce_apk_size task.

Criteria:
1. Bloat file (onboarding_deprecated.mp4) must be deleted from source (50 pts).
2. Project must compile successfully (30 pts).
3. Final APK size must be < 5MB (20 pts).
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reduce_apk_size(traj, env_info, task_info):
    """Verify that the APK size was reduced by removing the bloat asset."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Thresholds
    # The base Calculator app is usually small (< 3MB). 
    # The bloat file is 30MB.
    # Target size 5MB gives plenty of margin for the base app.
    TARGET_SIZE_BYTES = 5 * 1024 * 1024 

    score = 0
    feedback_parts = []

    # 1. Check Bloat File Removal (50 pts)
    bloat_exists = result.get("bloat_file_exists", True)
    if not bloat_exists:
        score += 50
        feedback_parts.append("Bloat file removed from source (50/50)")
    else:
        feedback_parts.append("Bloat file still exists in source (0/50)")

    # 2. Check Build Success (30 pts)
    build_success = result.get("build_success", False)
    if build_success:
        score += 30
        feedback_parts.append("Project rebuilds successfully (30/30)")
    else:
        feedback_parts.append("Project failed to rebuild (0/30)")

    # 3. Check APK Size (20 pts)
    apk_size = result.get("apk_size_bytes", 99999999)
    apk_size_mb = apk_size / (1024 * 1024)
    
    if apk_size < TARGET_SIZE_BYTES and apk_size > 0:
        score += 20
        feedback_parts.append(f"APK size optimized: {apk_size_mb:.2f}MB (20/20)")
    elif apk_size == 0:
        feedback_parts.append("APK file not found/size is 0 (0/20)")
    else:
        feedback_parts.append(f"APK size still too large: {apk_size_mb:.2f}MB (0/20)")

    # VLM Trajectory Check (Bonus/Verification of tool usage)
    # We want to see if they actually used the APK Analyzer or just deleted the file.
    # This is hard to strictly enforce via file state, so we use VLM.
    # If file is deleted and build passes, we give full score, but VLM adds confidence.
    
    passed = (score >= 80) # Must remove file and pass build at minimum

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }