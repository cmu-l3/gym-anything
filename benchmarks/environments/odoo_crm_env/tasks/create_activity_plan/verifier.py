#!/usr/bin/env python3
"""
Verifier for create_activity_plan task.
Checks if the Odoo Activity Plan was created and applied correctly.
"""

import json
import os
import tempfile
import logging
from datetime import datetime, date

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_activity_plan(traj, env_info, task_info):
    """
    Verifies:
    1. 'Standard Outreach' plan exists.
    2. Plan has 2 steps: Email (0 days) and Call (2 days).
    3. Opportunity 'Acme Corp Inquiry' has the scheduled activities.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    odoo_data = result.get("odoo_data", {})
    if "error" in odoo_data:
        return {"passed": False, "score": 0, "feedback": f"Odoo API Error: {odoo_data['error']}"}

    score = 0
    feedback_parts = []
    
    # 1. Check Plan Creation (20 pts)
    if odoo_data.get("plan_found"):
        score += 20
        feedback_parts.append("Plan 'Standard Outreach' created")
    else:
        feedback_parts.append("Plan 'Standard Outreach' NOT found")
        # Fail immediately if plan doesn't exist? 
        # We can continue to see if they manually scheduled activities, but core task is the plan.
    
    # 2. Check Plan Configuration (30 pts)
    # We look for specific steps in the plan steps list
    steps = odoo_data.get("plan_steps", [])
    
    email_step = next((s for s in steps if "intro packet" in str(s.get('summary', '')).lower()), None)
    call_step = next((s for s in steps if "follow-up call" in str(s.get('summary', '')).lower()), None)
    
    # Check Email Step
    if email_step:
        interval = email_step.get('plan_date_deadline_interval')
        if interval == 0:
            score += 15
            feedback_parts.append("Email step correct (0 days)")
        else:
            feedback_parts.append(f"Email step found but interval is {interval} (expected 0)")
    else:
        feedback_parts.append("Email step 'Intro Packet' missing in plan")

    # Check Call Step
    if call_step:
        interval = call_step.get('plan_date_deadline_interval')
        if interval == 2:
            score += 15
            feedback_parts.append("Call step correct (2 days)")
        else:
            feedback_parts.append(f"Call step found but interval is {interval} (expected 2)")
    else:
        feedback_parts.append("Call step 'Follow-up Call' missing in plan")

    # 3. Check Activities on Opportunity (50 pts total)
    activities = odoo_data.get("activities_found", [])
    
    # We expect 2 activities. One due today/tomorrow, one due ~2 days from now.
    # Since we can't be sure exactly when the agent ran it vs when we verify, 
    # we look for the EXISTENCE of the activities with the right summaries.
    
    act_intro = next((a for a in activities if "intro packet" in str(a.get('summary', '')).lower()), None)
    act_followup = next((a for a in activities if "follow-up call" in str(a.get('summary', '')).lower()), None)
    
    if act_intro:
        score += 25
        feedback_parts.append("Activity 'Intro Packet' found on opportunity")
        # Optional: Check date_deadline roughly matches today
    else:
        feedback_parts.append("Activity 'Intro Packet' NOT generated on opportunity")

    if act_followup:
        score += 25
        feedback_parts.append("Activity 'Follow-up Call' found on opportunity")
    else:
        feedback_parts.append("Activity 'Follow-up Call' NOT generated on opportunity")

    # Final check
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }