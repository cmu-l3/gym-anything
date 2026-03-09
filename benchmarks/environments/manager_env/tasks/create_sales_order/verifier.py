#!/usr/bin/env python3
"""
Verifier for Enable and Create Sales Order task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_sales_order(traj, env_info, task_info):
    """
    Verifies:
    1. Sales Orders module was enabled.
    2. Sales Order SO-90210 exists.
    3. Customer is Alfreds Futterkiste.
    4. Amount is 2400.00.
    5. Line item description is correct.
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

    score = 0
    feedback_parts = []
    
    # 1. Check if module enabled (20 pts)
    if result.get("module_enabled"):
        score += 20
        feedback_parts.append("Sales Orders module enabled.")
    else:
        feedback_parts.append("Sales Orders module NOT enabled.")

    # 2. Check if order found (20 pts)
    if result.get("order_found"):
        score += 20
        feedback_parts.append("Sales Order SO-90210 created.")
    else:
        feedback_parts.append("Sales Order SO-90210 NOT found.")

    # 3. Check Details (60 pts total)
    details = result.get("order_details", {})
    
    # Customer (20 pts)
    # Check both detail page scrape and list page fallback
    if details.get("customer") == "Alfreds Futterkiste" or details.get("customer_match_list"):
        score += 20
        feedback_parts.append("Correct Customer.")
    else:
        feedback_parts.append("Incorrect Customer.")

    # Amount (20 pts)
    if details.get("total") == 2400.0 or details.get("amount_match_list"):
        score += 20
        feedback_parts.append("Correct Amount (2,400.00).")
    else:
        feedback_parts.append("Incorrect Amount.")
        
    # Description (20 pts)
    if "Annual Priority Support" in details.get("description", "") or "Annual Priority Support Plan 2026" in details.get("description", ""):
        score += 20
        feedback_parts.append("Correct Line Item Description.")
    else:
        feedback_parts.append("Line Item Description mismatch or missing.")

    # Final Pass Check
    # Must have enabled module, created order, and got correct amount/customer
    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }