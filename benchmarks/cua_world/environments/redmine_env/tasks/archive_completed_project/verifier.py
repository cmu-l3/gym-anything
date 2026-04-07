#!/usr/bin/env python3
import json
import os
import tempfile
import time

def verify_archive_completed_project(traj, env_info, task_info):
    """
    Verifies that the project was archived and issues were closed with the correct note.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_issue_count = metadata.get('expected_issue_count', 5)
    
    # Copy result file from container
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

    # Scoring
    score = 0
    feedback_parts = []
    
    # 1. Check if project exists
    if not result.get("found"):
        return {"passed": False, "score": 0, "feedback": "Project 'office-relocation-2024' not found in database."}

    # 2. Check Project Status (Archived = 9)
    status_code = result.get("status_code")
    if status_code == 9:
        score += 30
        feedback_parts.append("Project is archived.")
    else:
        feedback_parts.append(f"Project status is {status_code} (expected 9/Archived).")

    # 3. Check Open Issues (Should be 0)
    open_issues = result.get("open_issues_count", -1)
    if open_issues == 0:
        score += 30
        feedback_parts.append("All issues are closed.")
    else:
        feedback_parts.append(f"{open_issues} issues represent still open.")

    # 4. Check Closing Notes
    matching_notes = result.get("matching_notes_count", 0)
    # We expect 5 issues to be updated. 
    # If they did a bulk edit, it creates 1 journal per issue.
    if matching_notes >= expected_issue_count:
        score += 20
        feedback_parts.append(f"Correct closing notes found on {matching_notes} issues.")
    elif matching_notes > 0:
        # Partial credit
        points = int((matching_notes / expected_issue_count) * 20)
        score += points
        feedback_parts.append(f"Correct closing notes found on only {matching_notes}/{expected_issue_count} issues.")
    else:
        feedback_parts.append("No issues found with the required closing note.")

    # 5. Logical Sequence / Anti-Gaming
    # If project is archived but issues are open, they failed step 3 (score penalty implicit).
    # If project is archived AND issues are closed, we assume valid sequence because 
    # you cannot easily close issues in an archived project without unarchiving.
    if status_code == 9 and open_issues == 0:
        score += 20
        feedback_parts.append("Workflow sequence (Close -> Archive) respected.")

    # Pass Threshold
    # Must archive AND close issues to pass
    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }