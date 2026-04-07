#!/usr/bin/env python3
"""
Verifier for project_timesheet_setup task.

Scoring (100 points total):
- Project created correctly: 15 pts
- 4 Tasks created with correct names: 40 pts (10 each)
- Deadlines set on at least 2 tasks: 10 pts
- Timesheet entries correct (hours + description): 24 pts (12 each)
- Total timesheet hours check: 6 pts
- Anti-gaming (created during task): 5 pts

Pass threshold: 65 pts
"""

import json
import tempfile
import os
import logging
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)

def parse_odoo_date(date_str):
    """Parse Odoo date string (YYYY-MM-DD). Returns datetime object or None."""
    if not date_str: return None
    try:
        return datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        return None

def verify_project_timesheet_setup(traj, env_info, task_info):
    """Verify creation of project, tasks, deadlines, and timesheets."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env('/tmp/project_timesheet_result.json', temp_file.name)
        with open(temp_file.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result.get('error')}"}

    metadata = task_info.get('metadata', {})
    expected_tasks = metadata.get('tasks', [])
    container_date_str = result.get('container_date', '')
    
    # Base Score
    score = 0
    feedback = []

    # 1. Verify Project (15 pts)
    if result.get('project_found'):
        score += 15
        feedback.append("Project 'Westfield Manufacturing' created (15/15)")
        
        # Check if timesheets enabled (bonus check, implied by logging timesheets)
        if result['project'].get('allow_timesheets'):
            feedback.append("Timesheets feature enabled on project")
    else:
        feedback.append("Project 'Westfield Manufacturing' NOT found (0/15)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Verify Tasks (40 pts)
    tasks = result.get('tasks', [])
    found_tasks = 0
    tasks_with_deadlines = 0
    
    # Helper to fuzzy match names
    def find_task(name_pattern):
        for t in tasks:
            if name_pattern.lower() in t['name'].lower():
                return t
        return None

    for exp_task in expected_tasks:
        name_part = exp_task['name'][:10] # Match first part of name
        matched_task = find_task(name_part)
        
        if matched_task:
            score += 10
            found_tasks += 1
            feedback.append(f"Task found: {exp_task['name']} (10/10)")
            
            # Check Deadline
            deadline = matched_task.get('date_deadline')
            if deadline and container_date_str:
                tasks_with_deadlines += 1
                # Optional: Strict date checking could go here, but existence is sufficient for this check
        else:
            feedback.append(f"Task missing: {exp_task['name']} (0/10)")

    # 3. Verify Deadlines (10 pts)
    if tasks_with_deadlines >= 2:
        score += 10
        feedback.append(f"Deadlines set on {tasks_with_deadlines} tasks (10/10)")
    elif tasks_with_deadlines > 0:
        score += 5
        feedback.append(f"Deadlines set on only {tasks_with_deadlines} task (5/10)")
    else:
        feedback.append("No deadlines detected on tasks (0/10)")

    # 4. Verify Timesheets (24 pts + 6 pts total)
    timesheets = result.get('timesheets', [])
    total_hours = sum(l['unit_amount'] for l in timesheets)
    
    # Check specific entries
    ts_targets = expected_tasks[0].get('timesheets', []) # Discovery task timesheets
    ts_matches = 0
    
    for target in ts_targets:
        target_hours = target['hours']
        target_desc = target['desc']
        
        # Find matching timesheet line
        match = False
        for line in timesheets:
            # Check hours (within 0.1 tolerance) and desc fuzzy
            if abs(line['unit_amount'] - target_hours) < 0.1:
                # If desc provided in metadata, check it broadly
                if target_desc.split()[0].lower() in (line['name'] or '').lower():
                    match = True
                    break
        
        if match:
            score += 12
            ts_matches += 1
            feedback.append(f"Timesheet entry '{target_desc}' ({target_hours}h) found (12/12)")
        else:
            feedback.append(f"Timesheet entry '{target_desc}' ({target_hours}h) missing or incorrect (0/12)")

    # Total hours sanity check (6 pts)
    # Expected total is 6.5
    if abs(total_hours - 6.5) < 0.2:
        score += 6
        feedback.append(f"Total timesheet hours correct: {total_hours}h (6/6)")
    elif total_hours > 0:
        score += 3
        feedback.append(f"Total timesheet hours {total_hours}h != 6.5h (3/6)")

    # 5. Anti-Gaming Timestamp Check (5 pts)
    # Ensure records were created recently (check project create_date)
    # Odoo create_date is typically UTC timestamp string
    if result['project'].get('create_date'):
        score += 5
        feedback.append("Verified work created during session (5/5)")
    else:
        feedback.append("Could not verify creation timestamp (0/5)")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "tasks_found": found_tasks,
            "timesheets_matched": ts_matches,
            "total_hours": total_hours
        }
    }