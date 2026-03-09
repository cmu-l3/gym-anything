#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_recurring_revenue(traj, env_info, task_info):
    """
    Verify the enable_recurring_revenue task.
    
    Criteria:
    1. Recurring Revenues setting enabled (implied by Plan creation success).
    2. 'Quarterly' plan created with 3-month duration.
    3. Opportunity created with correct revenues and plan link.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    feedback = []
    
    # 1. Check Plan Creation (30 pts)
    if result.get('plan_exists'):
        if result.get('plan_correct'):
            score += 30
            feedback.append("Recurring Plan 'Quarterly' created correctly (3 months).")
        else:
            score += 15
            feedback.append("Recurring Plan 'Quarterly' created, but duration is wrong.")
    else:
        feedback.append("Recurring Plan 'Quarterly' NOT found.")

    # 2. Check Opportunity Existence (20 pts)
    if result.get('opp_exists'):
        score += 20
        feedback.append("Opportunity 'Apex Logic - Enterprise Bundle' created.")
    else:
        feedback.append("Opportunity NOT found.")

    # 3. Check Opportunity Details (Revenues & Link) (50 pts total)
    raw_checks = result.get('raw_data', {}).get('checks', {})
    
    # One-time revenue (15 pts)
    if raw_checks.get('revenue_ok'):
        score += 15
        feedback.append("Expected Revenue (2500) correct.")
    elif result.get('opp_exists'):
        feedback.append("Expected Revenue incorrect.")

    # Recurring revenue (15 pts)
    if raw_checks.get('recurring_ok'):
        score += 15
        feedback.append("Recurring Revenue (600) correct.")
    elif result.get('opp_exists'):
        feedback.append("Recurring Revenue incorrect (field might be missing if setting disabled).")

    # Plan Link (20 pts)
    if raw_checks.get('plan_linked'):
        score += 20
        feedback.append("Opportunity correctly linked to 'Quarterly' plan.")
    elif result.get('opp_exists'):
        feedback.append("Opportunity NOT linked to 'Quarterly' plan.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }