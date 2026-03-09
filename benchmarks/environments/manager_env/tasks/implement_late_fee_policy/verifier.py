#!/usr/bin/env python3
"""
Verifier for implement_late_fee_policy task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_late_fee_policy(traj, env_info, task_info):
    """
    Verify the late fee implementation.
    
    Criteria:
    1. Account 'Late Fees Collected' created (20 pts)
    2. Item 'Late Fee' created (20 pts)
    3. Item linked to correct account (20 pts)
    4. Invoice created for Alfreds Futterkiste (20 pts)
    5. Invoice uses the created Item (not manual text) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    max_score = 100

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Criterion 1: Account Created
    if result.get("account_created"):
        score += 20
        feedback_parts.append("Income Account created successfully.")
    else:
        feedback_parts.append("Failed: 'Late Fees Collected' account not found.")

    # Criterion 2: Item Created
    if result.get("item_created"):
        score += 20
        feedback_parts.append("Late Fee item created.")
    else:
        feedback_parts.append("Failed: 'Late Fee' non-inventory item not found.")

    # Criterion 3: Item Linked
    if result.get("item_linked"):
        score += 20
        feedback_parts.append("Item correctly linked to income account.")
    else:
        if result.get("item_created") and result.get("account_created"):
             feedback_parts.append("Failed: Item exists but is NOT linked to the 'Late Fees Collected' account.")
        else:
             feedback_parts.append("Failed: Cannot verify link (missing item or account).")

    # Criterion 4: Invoice Created
    if result.get("invoice_created"):
        score += 20
        feedback_parts.append("Invoice to Alfreds Futterkiste found.")
    else:
        feedback_parts.append("Failed: No invoice to Alfreds Futterkiste found.")

    # Criterion 5: Item Usage
    if result.get("invoice_correct_item"):
        score += 20
        feedback_parts.append("Invoice correctly uses the 'Late Fee' item.")
    else:
        if result.get("invoice_created"):
            feedback_parts.append("Failed: Invoice found but does not use the linked 'Late Fee' item object (maybe typed manually?).")
        else:
            feedback_parts.append("Failed: No invoice to check for item usage.")

    # Final result
    passed = (score >= 80) # Allow one minor mistake, but generally requires workflow
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }