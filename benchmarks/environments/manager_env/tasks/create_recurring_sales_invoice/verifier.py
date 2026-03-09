#!/usr/bin/env python3
"""
Verifier for create_recurring_sales_invoice task.

Checks:
1. Recurring Sales Invoices tab is enabled (20pts)
2. A recurring invoice exists (15pts)
3. Customer is 'Alfreds Futterkiste' (20pts)
4. Line item description contains keywords (15pts)
5. Amount is 150.00 (15pts)
6. Interval is Monthly (10pts)
7. VLM workflow verification (5pts)
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_recurring_sales_invoice(traj, env_info, task_info):
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

    score = 0
    feedback = []
    
    # 1. Check Tab Enabled (20 pts)
    if result.get('tab_enabled', False):
        score += 20
        feedback.append("Recurring Sales Invoices tab enabled (+20)")
    else:
        feedback.append("FAIL: Recurring Sales Invoices tab NOT enabled")
        return {"passed": False, "score": 0, "feedback": "Tab not enabled - task failed"}

    # 2. Check Invoice Exists (15 pts)
    if result.get('invoice_found', False):
        score += 15
        feedback.append("Recurring invoice created (+15)")
    else:
        feedback.append("FAIL: No recurring invoice found")
        # Can't check details if invoice doesn't exist
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 3. Check Customer (20 pts)
    if result.get('customer_match', False):
        score += 20
        feedback.append("Customer correct (+20)")
    else:
        feedback.append("FAIL: Wrong customer")

    # 4. Check Description (15 pts)
    if result.get('description_match', False):
        score += 15
        feedback.append("Description correct (+15)")
    else:
        feedback.append("FAIL: Description mismatch")

    # 5. Check Amount (15 pts)
    if result.get('amount_match', False):
        score += 15
        feedback.append("Amount correct (+15)")
    else:
        feedback.append("FAIL: Amount mismatch (expected 150.00)")

    # 6. Check Interval (10 pts)
    if result.get('interval_match', False):
        score += 10
        feedback.append("Interval correct (+10)")
    else:
        feedback.append("FAIL: Interval mismatch (expected Monthly)")

    # 7. VLM Workflow Verification (5 pts)
    # Simple check: did they actually do work?
    task_duration = result.get('task_end', 0) - result.get('task_start', 0)
    if task_duration > 10:
        score += 5
        feedback.append("Workflow duration valid (+5)")
    else:
        feedback.append("SUSPICIOUS: Task completed too quickly")

    passed = score >= 65 and result.get('tab_enabled') and result.get('invoice_found')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }