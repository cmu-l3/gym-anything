#!/usr/bin/env python3
"""
Verifier for setup_service_item task.
Verifies:
1. "Consulting Revenue" account creation.
2. "Non-inventory Items" module enablement.
3. "Supply Chain Consulting" item creation and configuration (price, code, account link).
4. Sales Invoice creation using the item.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_service_item(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
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

    # Criterion 1: Account Creation (20 pts)
    if result.get("account_exists"):
        score += 20
        feedback.append("Income account 'Consulting Revenue' created.")
    else:
        feedback.append("Failed to create 'Consulting Revenue' account.")

    # Criterion 2: Module Enablement (10 pts)
    if result.get("module_enabled"):
        score += 10
        feedback.append("Non-inventory Items module enabled.")
    else:
        feedback.append("Non-inventory Items module not enabled.")

    # Criterion 3: Item Creation (20 pts)
    if result.get("item_exists"):
        score += 10
        feedback.append("Item 'Supply Chain Consulting' created.")
        if result.get("item_code_correct"):
            score += 5
            feedback.append("Item code correct.")
        if result.get("item_price_correct"):
            score += 5
            feedback.append("Item price correct.")
    else:
        feedback.append("Service item not found.")

    # Criterion 4: Item Linking (20 pts)
    if result.get("item_linked_correctly"):
        score += 20
        feedback.append("Item correctly linked to Consulting Revenue account.")
    elif result.get("item_exists"):
        feedback.append("Item NOT linked to the correct custom account.")

    # Criterion 5: Invoice Creation (15 pts)
    if result.get("invoice_exists") and result.get("invoice_total_correct"):
        if result.get("invoice_line_correct"):
            score += 15
            feedback.append("Invoice for Ernst Handel created correctly with service item.")
        else:
            score += 5
            feedback.append("Invoice created but missing specific service item.")
    else:
        feedback.append("Invoice for Ernst Handel ($1,000) not found.")

    # Criterion 6: VLM Workflow Verification (15 pts)
    # Ensure the user actually interacted with the settings/forms
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user using Manager.io accounting software.
    I am looking for evidence of the following workflow:
    1. Accessing 'Chart of Accounts' or 'Settings'.
    2. Editing or creating a 'Non-inventory Item'.
    3. Viewing or creating a 'Sales Invoice'.
    
    Do the screenshots show evidence of these distinct activities?
    Return JSON: {"workflow_visible": true/false, "confidence": "high/medium/low"}
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
        if vlm_res.get("parsed", {}).get("workflow_visible"):
            vlm_score = 15
            feedback.append("VLM confirmed workflow progression.")
        else:
            feedback.append("VLM could not confirm full workflow.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if program score is high, assume pass
        if score > 50:
            vlm_score = 15

    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }