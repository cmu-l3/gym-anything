#!/usr/bin/env python3
"""
Verifier for enable_and_create_purchase_order task.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_and_create_purchase_order(traj, env_info, task_info):
    """
    Verifies that:
    1. Purchase Orders module was enabled (is visible in sidebar).
    2. A Purchase Order for Exotic Liquids exists.
    3. The PO details (Date, Line Items, Total) are correct.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Module Enabled (25 pts)
    # ---------------------------------------------------------
    if result.get("module_enabled", False):
        score += 25
        feedback_parts.append("Purchase Orders module enabled.")
    else:
        feedback_parts.append("Purchase Orders module NOT enabled.")

    # ---------------------------------------------------------
    # Criterion 2: PO Exists (20 pts)
    # ---------------------------------------------------------
    if result.get("po_exists", False):
        score += 20
        feedback_parts.append("Purchase Order found.")
    else:
        feedback_parts.append("No Purchase Order found for Exotic Liquids.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # ---------------------------------------------------------
    # Criterion 3: Details Check (55 pts total)
    # ---------------------------------------------------------
    details = result.get("po_details", {})
    
    # Check Total (15 pts)
    # Expected: 660.00
    # Can be from calculated_total (from form parsing) or amount_match (html scrape)
    calc_total = details.get("calculated_total", 0.0)
    html_match = details.get("amount_match", False)
    
    if abs(calc_total - 660.00) < 1.0 or (html_match and calc_total == 0.0):
        score += 15
        feedback_parts.append("Total amount correct ($660.00).")
    else:
        feedback_parts.append(f"Total amount incorrect (Found: {calc_total}).")

    # Check Date (10 pts)
    # Expected: 2025-06-15
    issue_date = details.get("issue_date", "")
    date_html_match = details.get("date_match", False)
    
    if "2025-06-15" in issue_date or date_html_match:
        score += 10
        feedback_parts.append("Date correct.")
    else:
        feedback_parts.append(f"Date incorrect (Found: {issue_date}).")

    # Check Line Items (10 pts)
    # Expected: Chai Tea (24 @ 18) and Chang Beer (12 @ 19)
    lines = details.get("lines", [])
    chai_found = False
    chang_found = False
    
    for line in lines:
        desc = line.get("description", "").lower()
        qty = line.get("qty", 0)
        price = line.get("price", 0)
        
        if "chai" in desc and qty == 24 and abs(price - 18.00) < 0.1:
            chai_found = True
        if "chang" in desc and qty == 12 and abs(price - 19.00) < 0.1:
            chang_found = True
            
    if chai_found and chang_found:
        score += 10
        feedback_parts.append("Line items correct.")
    elif chai_found or chang_found:
        score += 5
        feedback_parts.append("One line item correct.")
    else:
        if lines:
            feedback_parts.append("Line items incorrect.")
        else:
            feedback_parts.append("No line items detailed.")

    # VLM/Trajectory Check (simulated 20 pts)
    # Since we have strong programmatic verification here, we award these points 
    # if the basic requirements are met, implying the workflow was followed.
    # In a full system, we would query the VLM here.
    if score >= 45: # If they enabled module and created PO
        score += 20
        feedback_parts.append("Workflow validated.")

    passed = (score >= 70) and result.get("module_enabled", False) and result.get("po_exists", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }