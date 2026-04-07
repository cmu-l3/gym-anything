#!/usr/bin/env python3
"""
Verifier for consolidate_duplicate_issues task.

Criteria:
1. Master issue (containing NullPointerException) identified and kept Open.
2. Duplicate issues (vague descriptions) marked as Rejected.
3. Duplicate issues linked to Master issue with "duplicates" relation.
4. Changes made *during* the task (anti-gaming).
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_duplicate_issues(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Data
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        copy_from_env("/tmp/task_meta.json", temp_meta.name)
        
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
        with open(temp_meta.name, 'r') as f:
            meta = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_meta.name): os.unlink(temp_meta.name)

    # 2. Parse Data
    issues = data.get('issues', [])
    task_start_time = meta.get('task_start_time', 0)
    
    if not issues:
        return {"passed": False, "score": 0, "feedback": "No issues found in project."}

    # 3. Identify Roles
    master_issue = None
    duplicates = []
    
    for i in issues:
        desc = i.get('description', '')
        if 'NullPointerException' in desc:
            master_issue = i
        else:
            duplicates.append(i)
            
    if not master_issue:
        return {"passed": False, "score": 0, "feedback": "Could not locate Master issue (with stack trace) in data."}

    # 4. Score Calculation
    score = 0
    feedback = []
    
    # CRITERION 1: Master Issue Status (30 pts)
    # Status should be New or Open (not Rejected/Closed)
    master_status = master_issue.get('status', '').lower()
    if master_status in ['new', 'open', 'in progress']:
        score += 30
        feedback.append("Master issue kept open.")
    elif master_status == 'rejected':
        feedback.append("FAIL: Master issue was Rejected.")
    else:
        feedback.append(f"Master issue status is {master_status} (acceptable).")
        score += 20 # Partial credit if status changed but not rejected

    # CRITERION 2: Duplicates Rejected (30 pts - 10 per duplicate)
    rejected_count = 0
    for d in duplicates:
        if d.get('status', '').lower() == 'rejected':
            rejected_count += 1
            
    # Normalize score based on count (expecting 3 duplicates)
    total_duplicates = len(duplicates)
    if total_duplicates > 0:
        status_score = int((rejected_count / total_duplicates) * 30)
        score += status_score
        feedback.append(f"{rejected_count}/{total_duplicates} duplicates rejected.")

    # CRITERION 3: Relations Created (30 pts)
    # Each duplicate should link TO master with type "duplicates"
    linked_count = 0
    for d in duplicates:
        relations = d.get('relations_from', [])
        is_linked = False
        for r in relations:
            # Relation: Duplicate IS DUPLICATE OF Master
            # So from_id=Duplicate, to_id=Master, type=duplicates
            if r.get('type') == 'duplicates' and r.get('target_id') == master_issue.get('id'):
                is_linked = True
                break
        if is_linked:
            linked_count += 1

    if total_duplicates > 0:
        link_score = int((linked_count / total_duplicates) * 30)
        score += link_score
        feedback.append(f"{linked_count}/{total_duplicates} duplicates linked to Master.")

    # CRITERION 4: Anti-Gaming / Timestamp Check (10 pts)
    # At least one issue must have been updated after task start
    work_done = False
    for i in issues:
        if i.get('updated_on', 0) > task_start_time:
            work_done = True
            break
            
    if work_done:
        score += 10
    else:
        feedback.append("FAIL: No issue timestamps updated during task window.")
        score = 0 # Fail immediately if no work recorded

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }