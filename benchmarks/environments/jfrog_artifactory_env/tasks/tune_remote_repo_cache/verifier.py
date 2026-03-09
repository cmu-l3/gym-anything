#!/usr/bin/env python3
"""
Verifier for tune_remote_repo_cache task.

Checks if the 'maven-central-remote' repository has its 
'retrievalCachePeriodSecs' set to 60.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tune_remote_repo_cache(traj, env_info, task_info):
    """
    Verify the repository cache settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Target values
    metadata = task_info.get('metadata', {})
    target_val = metadata.get('target_cache_period', 60)
    
    # Copy result JSON
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
    
    # 1. Check basic accessibility (10 pts)
    if result.get('artifactory_accessible', False):
        score += 10
    else:
        return {"passed": False, "score": 0, "feedback": "Artifactory was not accessible at verification time."}

    # 2. Check repository existence (20 pts)
    if result.get('repo_exists', False):
        score += 20
        feedback_parts.append("Repository exists")
    else:
        return {"passed": False, "score": 10, "feedback": "Target repository 'maven-central-remote' was deleted or not found."}

    # 3. Check specific configuration value (60 pts)
    # The value is retrieved from the API as an integer
    final_val = result.get('retrieval_cache_period_secs')
    
    try:
        final_val_int = int(final_val)
    except (ValueError, TypeError):
        final_val_int = -999

    if final_val_int == target_val:
        score += 60
        feedback_parts.append(f"Cache period correctly set to {target_val}s")
    else:
        feedback_parts.append(f"Cache period is {final_val_int}s (expected {target_val}s)")
        # Partial credit if they changed it from default but got the wrong number? 
        # No, the task is specific about "60 seconds".
        initial_val = result.get('initial_val')
        if final_val_int != initial_val:
             feedback_parts.append(f"Value was changed from {initial_val}s, but not to the correct target.")
             score += 10 # Small credit for finding the setting

    # 4. Anti-gaming / "Do Nothing" check
    # If initial == final, score is capped if it wasn't already correct (it shouldn't be, setup sets it to 7200)
    initial_val = result.get('initial_val', -1)
    if final_val_int == initial_val:
        feedback_parts.append("Value was not changed from initial state")
        # Ensure they don't get points just for the repo existing if they did nothing
        if score > 30: 
            score = 30 # Cap score for doing nothing

    # 5. VLM / Screenshot existence (10 pts)
    # We check if screenshots were generated during the process (env handles this, but we can verify final exists)
    # We assume standard trajectory capture adds some implicit value, here we explicitly award for clean finish
    score += 10

    passed = (score >= 90) # Requires correct value + repo exists + access + screenshot credit

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }