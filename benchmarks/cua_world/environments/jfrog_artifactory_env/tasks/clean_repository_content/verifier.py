#!/usr/bin/env python3
"""
Verifier for clean_repository_content task.

Verification Logic:
1. Repository Config Preserved (50 pts): 'example-repo-local' must still exist.
   - If the user deleted the entire repo, they fail this check.
2. Content Cleared (50 pts): The repository must be empty (0 files).
   - Partial deletion gets partial points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clean_repository_content(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Repository Existence (50 pts)
    # This is the "Safety" check - did they destroy the infrastructure?
    repo_exists = result.get("repo_exists", False)
    if repo_exists:
        score += 50
        feedback_parts.append("Repository configuration preserved (+50)")
    else:
        feedback_parts.append("CRITICAL: Repository was deleted entirely (0/50)")
        # If repo is gone, they technically 'cleaned' it, but failed the safety constraint.
        # We allow them to continue to score on emptiness? No, usually this is a major fail.
        # But per logic, if repo is gone, file count is 0, so they might get points there.
        # We should penalize heavily.
    
    # 2. Check Content Emptiness (50 pts)
    final_count = result.get("final_file_count", 999)
    artifact_1_gone = result.get("artifact_1_gone", False)
    artifact_2_gone = result.get("artifact_2_gone", False)
    
    if final_count == 0:
        score += 50
        feedback_parts.append("Repository is completely empty (+50)")
    else:
        # Partial credit if they deleted specific target files but left folders/others?
        # If the count is simply > 0, we check the known artifacts
        partial_score = 0
        if artifact_1_gone:
            partial_score += 20
        if artifact_2_gone:
            partial_score += 20
        
        score += partial_score
        feedback_parts.append(f"Repository not empty ({final_count} files remain). Partial credit: +{partial_score}")

    # Pass threshold
    # Must preserve repo AND empty it.
    passed = (score >= 100)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }