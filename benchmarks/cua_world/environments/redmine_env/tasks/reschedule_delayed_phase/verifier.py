#!/usr/bin/env python3
import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reschedule_delayed_phase(traj, env_info, task_info):
    """
    Verifies that the three wind farm tasks were rescheduled by +7 days
    and that a note was added to the first one.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_issues = metadata.get('issues', [])
    
    # 2. Retrieve Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Verification Logic
    score = 0
    max_score = 100
    feedback = []
    
    if not result.get('project_exists'):
        return {"passed": False, "score": 0, "feedback": "Project 'Coastal Wind Farm' not found."}

    retrieved_issues = result.get('issues', [])
    issue_map = {issue['subject']: issue for issue in retrieved_issues}

    # Points breakdown:
    # 3 issues * 30 points each (15 start date + 15 due date) = 90 points
    # 1 note = 10 points
    
    all_dates_correct = True
    
    for expected in expected_issues:
        subject = expected['subject']
        target_start = expected['target_start']
        target_due = expected['target_due']
        
        found_issue = issue_map.get(subject)
        
        if not found_issue:
            feedback.append(f"Issue '{subject}' not found.")
            all_dates_correct = False
            continue

        # Check Start Date
        actual_start = found_issue.get('start_date')
        if actual_start == target_start:
            score += 15
        else:
            feedback.append(f"'{subject}' start date is {actual_start}, expected {target_start}.")
            all_dates_correct = False

        # Check Due Date
        actual_due = found_issue.get('due_date')
        if actual_due == target_due:
            score += 15
        else:
            feedback.append(f"'{subject}' due date is {actual_due}, expected {target_due}.")
            all_dates_correct = False

        # Check Note (if required)
        if expected.get('check_note'):
            keyword = expected.get('note_keyword', '').lower()
            journals = found_issue.get('journals', [])
            note_found = False
            for journal in journals:
                notes = journal.get('notes', '').lower()
                if keyword in notes:
                    note_found = True
                    break
            
            if note_found:
                score += 10
            else:
                feedback.append(f"Missing note with keyword '{keyword}' on '{subject}'.")

    # 4. Final Assessment
    passed = (score >= 90) and all_dates_correct
    
    if passed:
        feedback.insert(0, "All tasks rescheduled correctly.")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }