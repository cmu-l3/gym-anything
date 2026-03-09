#!/usr/bin/env python3
"""
Verifier for chinook_encoding_repair task.

Scoring Criteria:
1. Data Integrity (60 points):
   - Artifacts remaining == 0 (Major points)
   - Correct characters present > 0 (Ensures no data deletion)
2. Deliverables (40 points):
   - Report CSV exists and created during task
   - SQL Script exists and created during task

Anti-gaming:
- Checks file timestamps
- Checks that data wasn't just deleted (via correct_chars_found)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_encoding_repair(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Data Integrity (Max 60 points)
    artifacts_remaining = result.get('artifacts_remaining', -1)
    correct_chars = result.get('correct_chars_found', -1)
    initial_artifacts = result.get('initial_artifacts', 0)

    if artifacts_remaining == -1:
        feedback_parts.append("Could not verify database content (DB missing?)")
    else:
        # Calculate cleanup progress
        if artifacts_remaining == 0:
            # Check if they just deleted everything
            if correct_chars > 0:
                score += 60
                feedback_parts.append("Database fully repaired (0 artifacts remaining, correct chars found)")
            else:
                score += 10
                feedback_parts.append("Artifacts gone, but NO correct characters found. Did you delete the data?")
        elif artifacts_remaining < initial_artifacts:
            # Partial credit
            progress = (initial_artifacts - artifacts_remaining) / initial_artifacts
            points = int(40 * progress)
            score += points
            feedback_parts.append(f"Partial repair: {artifacts_remaining} artifacts remaining (Progress: {int(progress*100)}%)")
        else:
            feedback_parts.append(f"No repair detected: {artifacts_remaining} artifacts remaining")

    # 2. CSV Report (Max 20 points)
    if result.get('report_exists'):
        if result.get('report_created_during_task'):
            score += 20
            feedback_parts.append("Summary report created")
        else:
            score += 5
            feedback_parts.append("Summary report exists but timestamp is old")
    else:
        feedback_parts.append("Summary report missing")

    # 3. SQL Script (Max 20 points)
    if result.get('script_exists'):
        if result.get('script_created_during_task'):
            score += 20
            feedback_parts.append("SQL script saved")
        else:
            score += 5
            feedback_parts.append("SQL script exists but timestamp is old")
    else:
        feedback_parts.append("SQL script missing")

    # Final Pass Check
    # Must have score >= 75 AND database effectively clean
    passed = (score >= 75) and (artifacts_remaining == 0) and (correct_chars > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }