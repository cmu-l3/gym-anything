#!/usr/bin/env python3
"""
Verifier for convert_item_type task.

Verification Checks:
1. Item 'Roe v. Wade' exists.
2. Item Type is 'Case' (ID 9).
3. Metadata fields match expected legal citation values.
4. Anti-gaming: The item modified must be the pre-existing one (created before task start), 
   not a newly created duplicate.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_convert_item_type(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load expected values
    meta = task_info.get('metadata', {})
    exp_name = meta.get('expected_case_name', 'Roe v. Wade')
    exp_court = meta.get('expected_court', 'United States Supreme Court')
    exp_rep = meta.get('expected_reporter', 'U.S.')
    exp_vol = meta.get('expected_volume', '410')
    exp_page = meta.get('expected_page', '113')
    exp_date = meta.get('expected_date', '1973')

    # Retrieve result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
        os.unlink(temp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve results: {e}"
        }

    score = 0
    feedback = []
    
    # 1. Check if item found
    if not result.get('item_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not find an item named 'Roe v. Wade' in the library.",
            "details": result
        }
    
    # 2. Check Item Type (Should be 9 for Case, was 24 for Article)
    type_id = result.get('item_type_id')
    if type_id == 9:
        score += 20
        feedback.append("Item type correctly changed to Case (+20)")
    elif type_id == 24:
        feedback.append("Item is still a Journal Article (Type ID 24)")
    else:
        feedback.append(f"Item has incorrect type ID: {type_id} (Expected 9)")

    # 3. Check Fields
    fields = result.get('fields', {})
    
    # Case Name (field 58)
    # Note: 'Roe v. Wade' was used to find the item, so this is likely correct if item_found is true
    # But we check if it is in the correct field (caseName vs title)
    if fields.get('caseName') == exp_name:
        score += 15
        feedback.append("Case Name correct (+15)")
    else:
        feedback.append(f"Case Name field missing or incorrect. Found title: {fields.get('title')}")

    # Court (field 60)
    # Allow partial match for "Supreme Court"
    val_court = fields.get('court', '')
    if "supreme" in val_court.lower() and "court" in val_court.lower():
        score += 15
        feedback.append(f"Court correct: {val_court} (+15)")
    else:
        feedback.append(f"Court incorrect. Expected '{exp_court}', got '{val_court}'")

    # Reporter (field 49)
    if fields.get('reporter') == exp_rep:
        score += 10
        feedback.append("Reporter correct (+10)")
    else:
        feedback.append(f"Reporter incorrect. Got '{fields.get('reporter')}'")

    # Volume (field 66)
    if str(fields.get('volume', '')) == str(exp_vol):
        score += 10
        feedback.append("Volume correct (+10)")
    else:
        feedback.append(f"Volume incorrect. Got '{fields.get('volume')}'")

    # Page (field 67)
    if str(fields.get('firstPage', '')) == str(exp_page):
        score += 10
        feedback.append("Page correct (+10)")
    else:
        feedback.append(f"Page incorrect. Got '{fields.get('firstPage')}'")

    # Date (field 69 for case decided, 8 for article date)
    # Jurism maps these differently. We want it in Date Decided (69).
    val_date = str(fields.get('dateDecided', ''))
    if exp_date in val_date:
        score += 10
        feedback.append("Date Decided correct (+10)")
    else:
        feedback.append(f"Date Decided incorrect. Got '{val_date}'")

    # 4. Anti-gaming
    # Must modify the original item (is_original_item=True)
    if result.get('is_original_item'):
        if result.get('was_modified_after_start'):
            score += 10
            feedback.append("Correctly modified the existing item (+10)")
        else:
            feedback.append("Item was not modified during the task")
    else:
        feedback.append("A NEW item was created instead of correcting the existing one. (0 pts for workflow)")
        score = 0 # Fail if they just made a new one instead of fixing the error
    
    passed = score >= 60 and type_id == 9

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }