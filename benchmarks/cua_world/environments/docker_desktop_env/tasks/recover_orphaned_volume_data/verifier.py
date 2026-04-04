#!/usr/bin/env python3
"""
Verifier for recover_orphaned_volume_data task.

The agent must identify an orphaned volume containing a specific project file
and mount it to a new container.

Scoring Breakdown (100 pts):
- 20 pts: Container 'recovery-env' is running
- 30 pts: Volume is mounted at '/workspace'
- 50 pts: The mounted volume contains the correct 'PROJECT_X_BLUEPRINT.md' with the session-specific secret token.
          (This validates the agent found the *right* volume and didn't just fake a file)

Pass Threshold: 100 pts (Strict recovery requirement)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_recover_orphaned_volume_data(traj, env_info, task_info):
    """Verify data recovery task."""
    
    # 1. Setup: Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read verification results: {e}. Did the export script run?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 3. Evaluate Criteria
    
    # Criterion 1: Container Running (20 pts)
    container_running = result.get('container_running', False)
    if container_running:
        score += 20
        feedback_parts.append("Recovery container is running (+20)")
    else:
        feedback_parts.append("Recovery container 'recovery-env' is NOT running (0/20)")

    # Criterion 2: Volume Mounted (30 pts)
    volume_mounted = result.get('volume_mounted', False)
    if volume_mounted:
        score += 30
        feedback_parts.append("Volume mounted at /workspace (+30)")
    else:
        feedback_parts.append("No volume mounted at /workspace (0/30)")

    # Criterion 3: Content Match (50 pts)
    # This implies the correct volume was found, as only the correct volume contains the secret token
    content_match = result.get('content_match', False)
    file_found = result.get('file_found', False)
    
    if content_match:
        score += 50
        feedback_parts.append("Correct data volume identified and verified (+50)")
    elif file_found:
        feedback_parts.append("File found but content did not match secret token. Did you modify the file or mount the wrong volume? (0/50)")
    else:
        feedback_parts.append("Target file 'PROJECT_X_BLUEPRINT.md' not found in mounted volume (0/50)")

    # Anti-gaming check (informational for feedback, but critical for logic)
    # If content matches, we know they found the right volume because the token is random per session.
    
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }