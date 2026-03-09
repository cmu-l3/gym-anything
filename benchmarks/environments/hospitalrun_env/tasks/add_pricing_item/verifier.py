#!/usr/bin/env python3
"""
Verifier for add_pricing_item task.

Multi-modal verification:
1. Database Content (Primary): Check if the correct pricing item exists in CouchDB.
2. Anti-Gaming: Check if the total count of pricing items increased.
3. VLM (Secondary): Verify trajectory shows the user navigating and interacting with the Pricing UI.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_pricing_item(traj, env_info, task_info):
    """
    Verifies that the agent added the specific pricing item to HospitalRun.
    """
    # 1. Setup and load data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Extract metadata expectations
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Portable Ultrasound - Limited Bedside')
    expected_price = float(metadata.get('expected_price', 275))
    expected_category = metadata.get('expected_category', 'Imaging')
    expected_expense = metadata.get('expected_expense_account', 'Radiology Services')

    # 2. Database Verification (Content)
    db_result = result.get('db_result', {})
    target_found = db_result.get('target_found', False)
    target_item = db_result.get('target_item', {}) or {}
    
    score = 0
    feedback_parts = []
    
    # CRITERION 1: Item created (15 pts)
    if target_found:
        score += 15
        feedback_parts.append("Pricing item created")
    else:
        feedback_parts.append("Pricing item NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # CRITERION 2: Fields Correct (60 pts total)
    # Name is already checked by 'target_found' logic in export script, but double check
    actual_name = target_item.get('name', '')
    if actual_name == expected_name:
        score += 15
        feedback_parts.append("Name matches")
    else:
        feedback_parts.append(f"Name mismatch ({actual_name})")

    # Price Check
    try:
        actual_price = float(target_item.get('price', 0))
        if abs(actual_price - expected_price) < 0.1:
            score += 20
            feedback_parts.append("Price matches")
        else:
            feedback_parts.append(f"Price mismatch ({actual_price})")
    except:
        feedback_parts.append("Price format error")

    # Category Check
    actual_category = target_item.get('category', '')
    if expected_category.lower() in actual_category.lower():
        score += 15
        feedback_parts.append("Category matches")
    else:
        feedback_parts.append(f"Category mismatch ({actual_category})")

    # Expense Account Check
    actual_expense = target_item.get('expenseAccount', '')
    if expected_expense.lower() in actual_expense.lower():
        score += 10
        feedback_parts.append("Expense account matches")
    else:
        feedback_parts.append(f"Expense account mismatch ({actual_expense})")

    # CRITERION 3: Anti-Gaming / Count Check (10 pts)
    initial_count = db_result.get('initial_count', 0)
    final_count = db_result.get('final_count', 0)
    if final_count > initial_count:
        score += 10
        feedback_parts.append("New record confirmed")
    else:
        feedback_parts.append("No record count increase")

    # CRITERION 4: VLM Trajectory Check (15 pts)
    # Use VLM to confirm they actually used the UI
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        prompt = """
        You are verifying a software agent's actions in HospitalRun.
        The agent was tasked with adding a new Pricing Item.
        
        Look at these screenshots of the agent's session.
        1. Did the agent navigate to the 'Pricing' section? (Look for 'Pricing' in sidebar or header)
        2. Did the agent fill out a form with price '275'?
        3. Did the agent save the item?
        
        Respond with JSON:
        {"ui_interaction_detected": true/false, "form_filled": true/false}
        """
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            vlm_data = vlm_resp.get('parsed', {}) if vlm_resp else {}
            
            if vlm_data.get('ui_interaction_detected'):
                score += 15
                feedback_parts.append("UI interaction verified")
            else:
                feedback_parts.append("UI interaction unclear")
        except Exception:
            # Fallback if VLM fails, grant points if DB record is perfect to avoid unfair fail
            if score >= 60:
                score += 15
                feedback_parts.append("VLM skipped")

    # Final pass determination
    # Must have the item created and reasonable correctness
    passed = (target_found and score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }