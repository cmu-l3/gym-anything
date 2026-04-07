#!/usr/bin/env python3
"""
Verifier for integrate_git_repository task.

Criteria:
1. 'Repositories' module enabled in project settings (30 pts)
2. Repository object exists (30 pts)
3. Repository type is Git (10 pts)
4. Repository path matches expected path exactly (30 pts)
"""

import json
import os
import tempfile

def verify_integrate_git_repository(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_path', '/var/lib/openproject/git/devops.git')
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_state = result.get('db_state', {})
    
    if not db_state.get('project_found'):
        return {"passed": False, "score": 0, "feedback": "Target project 'devops-automation' not found in database."}

    score = 0
    feedback = []

    # 1. Module Enabled (30 pts)
    if db_state.get('module_enabled'):
        score += 30
        feedback.append("Module 'Repositories' is enabled.")
    else:
        feedback.append("Module 'Repositories' is NOT enabled.")

    # 2. Repository Configured (30 pts)
    if db_state.get('repository_configured'):
        score += 30
        feedback.append("Repository configuration found.")
        
        # 3. SCM Type (10 pts)
        scm_type = str(db_state.get('scm_type', ''))
        if 'git' in scm_type.lower():
            score += 10
            feedback.append(f"SCM type is correct ({scm_type}).")
        else:
            feedback.append(f"Incorrect SCM type: {scm_type} (expected Git).")

        # 4. Path Match (30 pts)
        actual_path = str(db_state.get('repository_path', ''))
        # Normalize paths (strip trailing slashes, whitespace)
        norm_actual = actual_path.strip().rstrip('/')
        norm_expected = expected_path.strip().rstrip('/')
        
        if norm_actual == norm_expected:
            score += 30
            feedback.append(f"Repository path matches exactly: {actual_path}")
        else:
            feedback.append(f"Path mismatch. Expected: '{expected_path}', Found: '{actual_path}'")
    else:
        feedback.append("No repository configuration found for this project.")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }