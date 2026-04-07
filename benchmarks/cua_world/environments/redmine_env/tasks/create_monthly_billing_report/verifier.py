#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_monthly_billing_report(traj, env_info, task_info):
    """
    Verify the creation of the Monthly Billing View query.
    
    Scoring:
    - Query Exists: 30 pts
    - Created During Task: 10 pts
    - Group By Project: 20 pts
    - Public Visibility: 20 pts
    - Correct Columns (must include Comments): 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
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

    db_check = result.get('db_check', {})
    task_start = result.get('task_start', 0)
    
    score = 0
    feedback = []
    
    # Criterion 1: Query Exists (30 pts)
    if not db_check.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Custom query 'Monthly Billing View' was not found."
        }
    score += 30
    feedback.append("Query created.")

    # Criterion 2: Anti-gaming Timestamp (10 pts)
    created_on = db_check.get('created_on', 0)
    if created_on > task_start:
        score += 10
    else:
        feedback.append("Warning: Query timestamp predates task start.")

    # Criterion 3: Group By Project (20 pts)
    group_by = db_check.get('group_by')
    if group_by == 'project':
        score += 20
        feedback.append("Grouped by Project.")
    else:
        feedback.append(f"Incorrect grouping: {group_by} (expected 'project')")

    # Criterion 4: Public Visibility (20 pts)
    # Redmine visibility: 2 = Public (Any user), 0 = Private
    visibility = db_check.get('visibility')
    if visibility == 2:
        score += 20
        feedback.append("Visibility set to Public.")
    else:
        feedback.append("Visibility not set to 'Any user'.")

    # Criterion 5: Columns (20 pts)
    # Critical: 'comments' must be present. 'hours', 'user', 'activity', 'spent_on' (date) expected.
    # Note: Redmine internal column names: spent_on, user, activity, issue, comments, hours
    columns = db_check.get('columns', [])
    
    required_cols = ['comments', 'hours', 'activity', 'user', 'spent_on']
    missing_cols = [c for c in required_cols if c not in columns]
    
    if not missing_cols:
        score += 20
        feedback.append("All required columns present.")
    else:
        # Partial credit?
        if 'comments' in columns:
            score += 10
            feedback.append(f"Missing columns: {missing_cols}, but critical 'comments' field is present.")
        else:
            feedback.append(f"Missing critical column 'comments' and others: {missing_cols}")

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }