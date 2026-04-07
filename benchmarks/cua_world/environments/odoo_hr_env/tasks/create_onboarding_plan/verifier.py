#!/usr/bin/env python3
"""
Verifier for create_onboarding_plan task.
Checks database for:
1. 'New Employee Onboarding' plan existence.
2. Specific activity templates within the plan.
3. Activities launched on employee 'Eli Lambert'.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_onboarding_plan(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Odoo query error: {result['error']}"}

    score = 0
    feedback = []

    # Expected Configuration
    expected_templates = task_info.get('metadata', {}).get('expected_templates', [])
    
    # 1. Plan Existence (15 pts)
    if result.get("plan_found"):
        score += 15
        feedback.append("Plan 'New Employee Onboarding' created.")
    else:
        feedback.append("Plan 'New Employee Onboarding' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Activity Templates Check (50 pts total)
    # Breakdown: 20 for count, 20 for summaries, 10 for responsible types
    found_templates = result.get("templates", [])
    
    # Check count
    if len(found_templates) == 4:
        score += 20
        feedback.append("Correct number of templates (4).")
    else:
        feedback.append(f"Found {len(found_templates)} templates (expected 4).")
        # Partial credit for having some templates
        score += min(len(found_templates) * 5, 15)

    # Check content
    matched_summaries = 0
    matched_responsibles = 0
    
    # Normalize for comparison
    found_summary_map = {t.get('summary', '').strip().lower(): t for t in found_templates}
    
    for expected in expected_templates:
        exp_sum = expected['summary'].strip().lower()
        if exp_sum in found_summary_map:
            matched_summaries += 1
            # Check responsible
            found_resp = found_summary_map[exp_sum].get('responsible_type', '')
            if found_resp == expected['responsible_type']:
                matched_responsibles += 1
    
    # Score summaries (Max 20)
    score += (matched_summaries * 5)
    feedback.append(f"Matched {matched_summaries}/4 template summaries.")

    # Score responsible types (Max 10)
    score += (matched_responsibles * 2.5)
    feedback.append(f"Matched {matched_responsibles}/4 responsible assignments.")

    # 3. Plan Launch Verification (35 pts total)
    # Check if activities were created on Eli Lambert
    activities = result.get("employee_activities", [])
    
    # Filter for our specific onboarding activities in case there were others (though we cleared them)
    # We check if at least 3 of our expected summaries appear in the activities list
    found_activity_summaries = [a.get('summary', '').strip().lower() for a in activities]
    
    activities_matched = 0
    for expected in expected_templates:
        if expected['summary'].strip().lower() in found_activity_summaries:
            activities_matched += 1
            
    if activities_matched >= 4:
        score += 35
        feedback.append("All plan activities successfully launched for Eli Lambert.")
    elif activities_matched > 0:
        partial = activities_matched * 8
        score += partial
        feedback.append(f"Only {activities_matched}/4 activities launched for Eli Lambert.")
    else:
        feedback.append("No onboarding activities found on Eli Lambert's record.")

    passed = score >= 55 and result.get("plan_found") and activities_matched > 0

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }