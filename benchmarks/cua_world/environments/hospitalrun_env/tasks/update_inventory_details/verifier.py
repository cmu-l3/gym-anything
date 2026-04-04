#!/usr/bin/env python3
"""
Verifier for update_inventory_details task.

Checks if the inventory item 'Surgical Face Masks' in CouchDB 
has been updated with the correct location and price.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_inventory_details(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    target_location = metadata.get('target_location', 'ER Supply Cabinet')
    target_price = float(metadata.get('target_price', 15.50))
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback = []
    passed = False

    # 1. Check if item exists (20 pts)
    if not result.get('item_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The inventory item 'Surgical Face Masks' was not found in the database."
        }
    score += 20
    feedback.append("Item found in database.")

    # 2. Check Location (40 pts)
    actual_loc = result.get('location', '')
    # Case insensitive check might be nicer, but description was specific.
    # We'll allow slight whitespace diffs.
    if actual_loc and actual_loc.strip() == target_location:
        score += 40
        feedback.append(f"Location updated correctly to '{target_location}'.")
    else:
        feedback.append(f"Location incorrect. Expected '{target_location}', got '{actual_loc}'.")

    # 3. Check Price (40 pts)
    actual_price_raw = result.get('price')
    price_ok = False
    if actual_price_raw is not None:
        try:
            actual_price = float(str(actual_price_raw).replace('$','').replace(',',''))
            # Tolerance of 0.01
            if abs(actual_price - target_price) < 0.01:
                price_ok = True
                score += 40
                feedback.append(f"Price updated correctly to '{target_price}'.")
            else:
                feedback.append(f"Price incorrect. Expected '{target_price}', got '{actual_price}'.")
        except ValueError:
            feedback.append(f"Price format invalid. Got '{actual_price_raw}'.")
    else:
        feedback.append("Price field is missing or empty.")

    # Final Pass Logic
    if score >= 100:
        passed = True
    else:
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }