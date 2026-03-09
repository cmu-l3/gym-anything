#!/usr/bin/env python3
"""
Verifier for deploy_custom_gav_pom task.

Verifies:
1. JAR exists at the correct custom Maven path (not original filename).
2. POM exists at the correct path (implies 'Generate Default POM' was used).
3. JAR checksum matches source file.
4. Artifact was created during the task window.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deploy_custom_gav_pom(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result from container
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
    
    # 1. Verify JAR Existence (30 points)
    if result.get("jar_exists", False):
        score += 30
        feedback_parts.append("JAR deployed to correct custom path.")
    else:
        feedback_parts.append(f"JAR NOT found at expected path: {result.get('jar_path_checked')}.")

    # 2. Verify POM Existence (30 points)
    # This proves the user mapped coordinates and generated the POM
    if result.get("pom_exists", False):
        score += 30
        feedback_parts.append("POM file generated successfully.")
    else:
        feedback_parts.append("POM file NOT found (Did you check 'Generate Default POM'?).")

    # 3. Verify Checksum (20 points)
    deployed_sum = result.get("deployed_sha256", "")
    source_sum = result.get("source_sha256", "")
    if deployed_sum and source_sum and deployed_sum == source_sum:
        score += 20
        feedback_parts.append("Artifact integrity verified (checksum match).")
    else:
        if result.get("jar_exists"):
            feedback_parts.append("Checksum mismatch - deployed file content differs from source.")
        
    # 4. Anti-Gaming: Created During Task (20 points)
    if result.get("created_during_task", False):
        score += 20
    elif result.get("jar_exists"):
        feedback_parts.append("Artifact has old timestamp (pre-task).")

    # Final Verdict
    # Must have JAR and POM at minimum to pass
    passed = result.get("jar_exists") and result.get("pom_exists") and score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }