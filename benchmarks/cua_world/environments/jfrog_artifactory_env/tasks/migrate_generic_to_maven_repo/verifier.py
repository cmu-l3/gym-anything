#!/usr/bin/env python3
"""
Verifier for migrate_generic_to_maven_repo task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_generic_to_maven_repo(traj, env_info, task_info):
    """
    Verifies the repository migration task.
    
    Criteria:
    1. New repository 'libs-commons-local' exists (30 pts)
    2. New repository is of type 'Maven' (20 pts)
    3. Artifacts exist in the new repository (30 pts)
    4. Old repository 'temp-uploads' is deleted (20 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Target Repo Existence (30 pts)
    if result.get('target_repo_exists', False):
        score += 30
        feedback_parts.append("Target repository created")
    else:
        feedback_parts.append("Target repository 'libs-commons-local' NOT found")

    # 2. Check Target Repo Type (20 pts)
    # The shell script exports the package type in lowercase
    repo_type = result.get('target_repo_type', 'unknown')
    if repo_type == 'maven':
        score += 20
        feedback_parts.append("Target repository is correct type (Maven)")
    elif result.get('target_repo_exists', False):
        feedback_parts.append(f"Target repository has wrong type: {repo_type}")
    
    # 3. Check Artifact Migration (30 pts)
    if result.get('artifact_exists_in_target', False):
        score += 30
        feedback_parts.append("Artifacts successfully migrated")
    else:
        feedback_parts.append("Artifacts NOT found in target repository")

    # 4. Check Old Repo Deletion (20 pts)
    if not result.get('source_repo_exists', True):
        score += 20
        feedback_parts.append("Source repository deleted")
    else:
        feedback_parts.append("Source repository 'temp-uploads' still exists")

    # Final logic
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }