#!/usr/bin/env python3
"""
Verifier for create_project_portfolio_view task.

Criteria:
1. Query exists with name "PMO Portfolio" (30 pts)
2. Visibility is Public (20 pts)
3. Columns match expected set (30 pts)
4. Sort order is Created on (Descending) (20 pts)
5. Anti-gaming: Created after task start
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_project_portfolio_view(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result file
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
    
    # 2. Check Existence (30 pts)
    found = result.get('found', False)
    if not found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Saved view 'PMO Portfolio' was not found in the database."
        }
    
    score += 30
    feedback_parts.append("View 'PMO Portfolio' created")

    # 3. Check Anti-Gaming (Timestamp)
    # The query creation time must be > task start time
    created_at = result.get('created_at', 0)
    task_start = result.get('task_start_time', 0)
    
    if created_at < task_start:
        return {
            "passed": False,
            "score": 0,
            "feedback": "The view appears to be pre-existing (created before task start). Please recreate it."
        }

    # 4. Check Visibility (20 pts)
    is_public = result.get('is_public', False)
    if is_public:
        score += 20
        feedback_parts.append("Visibility is Public")
    else:
        feedback_parts.append("Visibility is NOT Public (0/20)")

    # 5. Check Columns (30 pts)
    # Expected: name, status, description, created_on
    # OpenProject might internally name them: "name", "status" (or "project_status"), "description", "created_on"
    actual_columns = [c.lower() for c in result.get('columns', [])]
    
    # "project_status" is sometimes used instead of "status", handle both
    normalized_columns = []
    for c in actual_columns:
        if c == 'project_status': normalized_columns.append('status')
        else: normalized_columns.append(c)
        
    required_set = {'name', 'status', 'description', 'created_on'}
    actual_set = set(normalized_columns)
    
    # Check if all required are present
    missing = required_set - actual_set
    if not missing:
        score += 30
        feedback_parts.append("Columns correct")
    else:
        # Partial credit? No, description is specific
        feedback_parts.append(f"Missing columns: {', '.join(missing)} (0/30)")

    # 6. Check Sort Order (20 pts)
    # Expected: [['created_on', 'desc']]
    sort_criteria = result.get('sort_criteria', [])
    
    # Sort criteria structure from Rails is typically [['created_on', 'desc']]
    # Depending on version it might use strings or symbols, exported as strings by our script
    is_sorted_correctly = False
    
    if sort_criteria and len(sort_criteria) > 0:
        first_sort = sort_criteria[0]
        # Check field (created_on) and direction (desc)
        if len(first_sort) >= 2:
            field = str(first_sort[0])
            direction = str(first_sort[1]).lower()
            if field == 'created_on' and direction == 'desc':
                is_sorted_correctly = True
    
    if is_sorted_correctly:
        score += 20
        feedback_parts.append("Sort order correct")
    else:
        feedback_parts.append(f"Sort order incorrect (expected Created on Descending, got {sort_criteria}) (0/20)")

    # Final Pass Determination
    # Threshold: 70 points
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }