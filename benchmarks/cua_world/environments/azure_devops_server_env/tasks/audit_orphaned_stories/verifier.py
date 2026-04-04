#!/usr/bin/env python3
import json
import logging
import os
import tempfile
import re

logger = logging.getLogger(__name__)

def verify_audit_orphaned_stories(traj, env_info, task_info):
    """
    Verify the Audit Orphaned Stories task.
    
    Criteria:
    1. Query exists in 'Shared Queries' named 'Stories without Tasks' (20 pts)
    2. Query Type is 'OneHop' (Work items and direct links) (20 pts)
    3. Query Logic checks 'Does not contain' link (20 pts)
    4. Query Source filters for 'User Story' (15 pts)
    5. Query Target filters for 'Task' (15 pts)
    6. Execution returns exactly the expected orphaned items (10 pts)
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\task_results\\audit_orphaned_stories_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback = []
    
    # 1. Check Existence
    if result.get('query_found'):
        score += 20
        feedback.append("Query 'Stories without Tasks' found in Shared Queries.")
    else:
        return {"passed": False, "score": 0, "feedback": "Query 'Stories without Tasks' NOT found in Shared Queries."}

    # 2. Check Query Type
    # ADO API returns 'oneHop' for "Work items and direct links"
    q_type = result.get('query_type', '').lower()
    if q_type == 'onehop':
        score += 20
        feedback.append("Correct Query Type (Work items and direct links).")
    else:
        feedback.append(f"Incorrect Query Type: {q_type} (Expected 'Work items and direct links').")

    # 3-5. Check WIQL Logic
    wiql = result.get('query_wiql', '').lower()
    
    # Check Source (User Story)
    if "from workitemlinks" in wiql:
        # Check source side (Source.[System.WorkItemType] = 'User Story')
        if "source.[system.workitemtype] = 'user story'" in wiql or "source.[system.workitemtype] = 'user story'" in wiql.replace("'", '"'):
            score += 15
            feedback.append("Correctly filters Source for 'User Story'.")
        else:
            feedback.append("Missing or incorrect Source filter for 'User Story'.")
            
        # Check Target (Task)
        if "target.[system.workitemtype] = 'task'" in wiql or "target.[system.workitemtype] = 'task'" in wiql.replace("'", '"'):
            score += 15
            feedback.append("Correctly filters Target for 'Task'.")
        else:
            feedback.append("Missing or incorrect Target filter for 'Task'.")
            
        # Check Mode (Does Not Contain)
        # In WIQL, this looks like "mode(DoesNotContain)"
        if "mode(doesnotcontain)" in wiql:
            score += 20
            feedback.append("Correctly uses 'Does Not Contain' link logic.")
        else:
            feedback.append("Incorrect Link Logic (Expected 'Does Not Contain').")
            
    else:
        feedback.append("WIQL does not appear to be a Link query (missing 'From WorkItemLinks').")

    # 6. Check Execution Result
    # We expect 2 orphaned items
    count = result.get('execution_count', 0)
    if count == 2:
        score += 10
        feedback.append("Query returns the correct number of orphaned items (2).")
    else:
        feedback.append(f"Query returned {count} items (Expected 2).")

    # Final Verification
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }