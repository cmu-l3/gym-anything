#!/usr/bin/env python3
"""
Verifier for import_issues_from_csv task.
Verifies that issues were correctly imported into Redmine from a CSV file.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_issues_from_csv(traj, env_info, task_info):
    """
    Verify 8 issues were imported with correct attributes.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_issues = metadata.get('expected_issues', [])
    min_expected_count = metadata.get('expected_count', 8)

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    actual_issues = result.get('issues', [])
    total_count = result.get('total_issue_count', 0)
    task_start = result.get('task_start', 0)

    score = 0
    feedback = []

    # Criterion 1: Issue Count (25 pts)
    if total_count >= min_expected_count:
        score += 25
        feedback.append(f"Found {total_count} issues (target: {min_expected_count}).")
    else:
        feedback.append(f"Found only {total_count} issues (target: {min_expected_count}).")

    # Helper to find issue by subject
    def find_issue_by_subject(subj):
        for issue in actual_issues:
            if issue.get('subject') == subj:
                return issue
        return None

    # Criteria 2-5: Verify Content (Subjects, Trackers, Priorities, Estimated Hours)
    # We verify each expected issue against the actual list
    issues_found = 0
    trackers_correct = 0
    priorities_correct = 0
    hours_correct = 0
    
    # Weights calculation
    # 8 issues * 4 attributes = 32 checks
    # Total remaining points = 65 (25 for count, 10 for timestamps)
    # Roughly: 
    # Subjects: 25 pts
    # Trackers: 15 pts
    # Priorities: 15 pts
    # Hours: 10 pts

    for expected in expected_issues:
        found = find_issue_by_subject(expected['subject'])
        
        if found:
            issues_found += 1
            
            # Check Tracker
            # Redmine API returns tracker as object: {"id": 1, "name": "Bug"}
            actual_tracker = found.get('tracker', {}).get('name', '')
            if actual_tracker == expected['tracker']:
                trackers_correct += 1
            
            # Check Priority
            # Redmine API returns priority as object: {"id": 2, "name": "Normal"}
            actual_priority = found.get('priority', {}).get('name', '')
            if actual_priority == expected['priority']:
                priorities_correct += 1
            
            # Check Estimated Hours
            # Redmine API returns estimated_hours as float or null
            actual_hours = found.get('estimated_hours')
            if actual_hours is not None:
                try:
                    if abs(float(actual_hours) - expected['estimated_hours']) < 0.1:
                        hours_correct += 1
                except ValueError:
                    pass
        else:
            feedback.append(f"Missing issue: {expected['subject']}")

    # Apply scores
    # Subject matching (25 pts max)
    score += (issues_found / len(expected_issues)) * 25
    
    # Tracker matching (15 pts max)
    score += (trackers_correct / len(expected_issues)) * 15
    
    # Priority matching (15 pts max)
    score += (priorities_correct / len(expected_issues)) * 15
    
    # Hours matching (10 pts max)
    score += (hours_correct / len(expected_issues)) * 10

    # Criterion 6: Timestamp Anti-Gaming (10 pts)
    # Check that at least one issue was created after task start
    # Redmine API created_on format: "2024-03-08T10:00:00Z"
    timestamps_valid = False
    valid_count = 0
    
    for issue in actual_issues:
        created_str = issue.get('created_on', '')
        try:
            # Parse ISO8601
            created_dt = datetime.strptime(created_str, "%Y-%m-%dT%H:%M:%SZ")
            created_ts = created_dt.timestamp()
            
            if created_ts > task_start:
                valid_count += 1
        except Exception:
            pass # Ignore parsing errors

    if valid_count >= min_expected_count:
        score += 10
        timestamps_valid = True
        feedback.append("Timestamps validated.")
    elif valid_count > 0:
        score += 5
        feedback.append(f"Partial timestamp validation ({valid_count}/{min_expected_count}).")
    else:
        feedback.append("No issues created after task start time.")

    # Pass Threshold
    # Requires 50 points (at least count and subjects correct)
    passed = score >= 50 and total_count >= min_expected_count
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback),
        "details": {
            "total_count": total_count,
            "issues_matched": issues_found,
            "trackers_correct": trackers_correct,
            "priorities_correct": priorities_correct,
            "hours_correct": hours_correct
        }
    }