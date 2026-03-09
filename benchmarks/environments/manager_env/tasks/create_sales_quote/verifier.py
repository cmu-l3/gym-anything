#!/usr/bin/env python3
"""
Verifier for create_sales_quote task in Manager.io.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_sales_quote(traj, env_info, task_info):
    """
    Verifies the Sales Quote creation task.
    
    Criteria:
    1. Sales Quotes module enabled (15 pts)
    2. Quote created and found (10 pts)
    3. Correct Customer (15 pts)
    4. Correct Line Items (15 pts for presence, 10 for details)
    5. Correct Totals (5 pts)
    6. Correct Dates (5 pts)
    7. VLM verification of workflow (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Programmatic Verification (from exported JSON)
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

    score = 0
    feedback = []

    # Check Module Enabled
    if result.get("module_enabled"):
        score += 15
        feedback.append("Sales Quotes module enabled.")
    else:
        feedback.append("Sales Quotes module NOT enabled.")

    # Check Quote Existence
    if result.get("quote_found"):
        score += 10
        feedback.append("Sales Quote found.")
    else:
        feedback.append("Sales Quote NOT found.")

    # Check Customer
    if result.get("customer_match"):
        score += 15
        feedback.append("Customer matches 'Alfreds Futterkiste'.")
    else:
        feedback.append("Customer mismatch.")

    # Check Line Items
    lines = result.get("line_items", [])
    if len(lines) >= 3:
        score += 15
        feedback.append("All 3 line items found.")
    elif len(lines) > 0:
        score += 5 * len(lines)
        feedback.append(f"Only {len(lines)}/3 line items found.")
    else:
        feedback.append("No correct line items found.")

    # Check Total Amount
    if abs(result.get("total_amount", 0) - 667.50) < 1.0:
        score += 5
        feedback.append("Total amount correct (667.50).")
    else:
        feedback.append(f"Total amount mismatch (Found: {result.get('total_amount')}).")

    # Check Dates
    if result.get("date_match") and result.get("expiry_match"):
        score += 5
        feedback.append("Dates correct.")
    elif result.get("date_match") or result.get("expiry_match"):
        score += 2
        feedback.append("One date correct.")

    # 2. VLM Verification (Trajectory Analysis)
    # We verify the agent actually navigated settings and filled the form
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user using Manager.io accounting software.
    Look for these specific workflow steps:
    1. Navigation to 'Settings' or 'Customize' screen.
    2. Enabling a checkbox for 'Sales Quotes'.
    3. Filling out a 'Sales Quote' form with line items.
    4. A final view showing the created quote.
    
    Return JSON:
    {
        "settings_accessed": true/false,
        "module_enabled_visually": true/false,
        "form_filled": true/false,
        "final_quote_visible": true/false
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("settings_accessed") or parsed.get("module_enabled_visually"):
            vlm_score += 10
            feedback.append("VLM confirmed settings/module configuration.")
        if parsed.get("form_filled"):
            vlm_score += 10
            feedback.append("VLM confirmed form filling.")
        if parsed.get("final_quote_visible"):
            vlm_score += 5
            feedback.append("VLM confirmed final quote visibility.")
    
    score += vlm_score

    # Final Pass Determination
    # Must have enabled module + created quote + got most details right
    passed = (score >= 60) and result.get("module_enabled") and result.get("quote_found")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }