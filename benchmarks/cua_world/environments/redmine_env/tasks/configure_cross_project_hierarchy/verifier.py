#!/usr/bin/env python3
"""
Verifier for configure_cross_project_hierarchy task.

Criteria:
1. Global Setting 'cross_project_subtasks' must be set to 'system' (With all projects) (40 pts)
2. The specific child issue must have the specific parent issue set as its parent (40 pts)
3. The parent issue must be the correct one (sanity check) (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_cross_project_hierarchy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    # Extract data
    setting_value = result.get('setting_value', '')
    child_parent_id = result.get('child_parent_id')
    parent_issue_id = result.get('parent_issue_id')
    child_project = result.get('child_project_id')
    parent_project = result.get('parent_project_id')

    score = 0
    feedback = []
    
    # 1. Check Setting (40 pts)
    # Redmine stores "With all projects" as 'system'
    if setting_value == 'system':
        score += 40
        feedback.append("Global setting 'Allow cross-project subtasks' correctly enabled.")
    else:
        feedback.append(f"Global setting incorrect. Expected 'system' (With all projects), got '{setting_value}'.")

    # 2. Check Parent ID Linkage (40 pts)
    if child_parent_id is not None and parent_issue_id is not None:
        if int(child_parent_id) == int(parent_issue_id):
            score += 40
            feedback.append("Child issue is correctly linked to parent issue.")
        else:
            feedback.append(f"Child issue linked to wrong parent. Expected ID {parent_issue_id}, got {child_parent_id}.")
    else:
        feedback.append("Child issue has no parent set.")

    # 3. Cross-project verification (20 pts)
    # Ensure they are actually in different projects (verifies the task premise was maintained)
    if child_project != parent_project and child_project == 'propulsion-sys' and parent_project == 'corp-strategy':
        if score >= 80: # Only award these points if the main task was done
            score += 20
            feedback.append("Verified cross-project boundary crossed.")
    
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }