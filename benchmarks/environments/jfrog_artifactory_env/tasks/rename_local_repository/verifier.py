#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rename_local_repository(traj, env_info, task_info):
    """
    Verify the 'rename' repository task.
    
    Expected Outcome:
    1. 'module-core-local' exists (Created).
    2. 'legacy-dev-local' does NOT exist (Deleted).
    3. Artifact exists in 'module-core-local' (Migrated).
    """
    
    # 1. Retrieve result data from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Extract Data
    target_repo_exists = result.get('target_repo_exists', False)
    source_repo_exists = result.get('source_repo_exists', True)
    artifact_migrated = result.get('artifact_migrated', False)
    artifact_size = result.get('artifact_size_bytes', 0)
    
    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: New Repository Created (30 pts)
    if target_repo_exists:
        score += 30
        feedback_parts.append("Target repository 'module-core-local' created.")
    else:
        feedback_parts.append("Target repository 'module-core-local' NOT found.")
        
    # Criterion 2: Content Migrated (40 pts)
    if artifact_migrated:
        if artifact_size > 0:
            score += 40
            feedback_parts.append("Artifact successfully migrated to new repository.")
        else:
            score += 20 # Partial credit if file exists but is empty/corrupt
            feedback_parts.append("Artifact exists but appears empty.")
    else:
        feedback_parts.append("Artifact NOT found in new repository.")
        
    # Criterion 3: Old Repository Deleted (30 pts)
    if not source_repo_exists:
        score += 30
        feedback_parts.append("Source repository 'legacy-dev-local' deleted.")
    else:
        feedback_parts.append("Source repository 'legacy-dev-local' still exists (should be deleted).")
        
    # 4. Final Assessment
    # Strict pass: Must have completed all 3 parts (Rename = Copy + Delete)
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }