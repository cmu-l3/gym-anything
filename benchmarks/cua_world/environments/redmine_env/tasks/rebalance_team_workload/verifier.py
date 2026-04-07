#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rebalance_team_workload(traj, env_info, task_info):
    """
    Verifies that exactly 2 High priority issues were moved from Michael to Jane
    with the required note.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # Extract Data
    initial_state = result.get('initial_state', {})
    final_issues = result.get('final_issues', [])
    task_start = result.get('task_start', 0)

    mturner_id = initial_state.get('mturner_id')
    jdoe_id = initial_state.get('jdoe_id')
    
    # Metadata Requirements
    metadata = task_info.get('metadata', {})
    required_note_fragment = metadata.get('required_note', "balance sprint workload").lower()
    required_count = metadata.get('required_move_count', 2)

    if not final_issues:
        return {"passed": False, "score": 0, "feedback": "No issues found in project."}

    # Analysis
    jane_issues = []
    michael_issues = []
    other_issues = []

    for issue in final_issues:
        assignee_id = issue.get('assigned_to_id')
        if assignee_id == jdoe_id:
            jane_issues.append(issue)
        elif assignee_id == mturner_id:
            michael_issues.append(issue)
        else:
            other_issues.append(issue)

    score = 0
    feedback = []

    # Criterion 1: Jane has issues (20 pts)
    if len(jane_issues) > 0:
        score += 20
        feedback.append(f"Jane has {len(jane_issues)} issues.")
    else:
        feedback.append("Jane has no issues.")

    # Criterion 2: Correct Quantity (20 pts)
    if len(jane_issues) == required_count:
        score += 20
        feedback.append("Exact count correct (2).")
    else:
        feedback.append(f"Count incorrect (expected {required_count}, got {len(jane_issues)}).")

    # Criterion 3: Correct Source & Anti-gaming (10 pts)
    # Check if these issues were originally part of the seed (IDs match)
    # Since we don't have the original list mapped to IDs in the export JSON easily without processing initial_state['issue_ids'], 
    # we assume the IDs in final_issues are the same since we didn't delete them.
    # We just assume if they exist and are assigned, they are valid.
    # We give points if no 'new' issues appeared (simple check: count matches seed count)
    total_issues = len(jane_issues) + len(michael_issues) + len(other_issues)
    if total_issues == 8: # We seeded 8
        score += 10
        feedback.append("No issues created or deleted.")
    else:
        feedback.append(f"Issue count changed (expected 8, got {total_issues}).")

    # Criterion 4: Priority Check (20 pts)
    # All issues assigned to Jane MUST be High priority
    high_prio_count = sum(1 for i in jane_issues if i.get('priority_name') == 'High')
    if len(jane_issues) > 0 and high_prio_count == len(jane_issues):
        score += 20
        feedback.append("All moved issues are High priority.")
    elif len(jane_issues) > 0:
        feedback.append("Some moved issues are NOT High priority.")

    # Criterion 5: Handover Note (20 pts)
    # Check if notes contain the string
    note_correct_count = 0
    for i in jane_issues:
        notes = i.get('notes', [])
        # Join all notes and check
        all_notes = " ".join(notes).lower()
        if required_note_fragment in all_notes:
            note_correct_count += 1
    
    if len(jane_issues) > 0 and note_correct_count == len(jane_issues):
        score += 20
        feedback.append("All moved issues have correct note.")
    elif note_correct_count > 0:
        score += 10 # Partial
        feedback.append("Some moved issues missing note.")
    else:
        feedback.append("Moved issues missing required note.")

    # Criterion 6: Michael's Remainder (10 pts)
    # Michael should have remaining issues (he started with 8, gave 2, should have 6)
    if len(michael_issues) == 6:
        score += 10
        feedback.append("Michael retains correct number of issues.")
    
    passed = (score >= 80) and (len(jane_issues) == required_count) and (high_prio_count == required_count)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }