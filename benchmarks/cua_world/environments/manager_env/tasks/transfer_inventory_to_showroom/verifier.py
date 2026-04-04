#!/usr/bin/env python3
"""
Verifier for transfer_inventory_to_showroom task.
"""

import json
import os
import tempfile
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transfer_inventory(traj, env_info, task_info):
    """
    Verify that the user enabled modules, created a location, and transferred stock.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_location = metadata.get("expected_location_name", "Showroom")
    expected_item = metadata.get("expected_item_name", "Chai")
    expected_qty = metadata.get("expected_qty", 40)
    expected_date = metadata.get("expected_date", "2026-05-01")

    # Load result
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

    manager_data = result.get("manager_data", {})
    modules_enabled = manager_data.get("modules_enabled", [])
    locations = manager_data.get("locations", [])
    transfers = manager_data.get("transfers", [])

    score = 0
    feedback_parts = []
    
    # 1. Check Modules (20 pts)
    # Both InventoryLocations and InventoryTransfers must be enabled
    if "InventoryLocations" in modules_enabled and "InventoryTransfers" in modules_enabled:
        score += 20
        feedback_parts.append("Modules enabled correctly")
    elif "InventoryLocations" in modules_enabled or "InventoryTransfers" in modules_enabled:
        score += 10
        feedback_parts.append("Only some modules enabled")
    else:
        feedback_parts.append("Required modules NOT enabled")

    # 2. Check Location (20 pts)
    location_found = False
    for loc in locations:
        if expected_location.lower() in loc.get("name", "").lower():
            location_found = True
            break
    
    if location_found:
        score += 20
        feedback_parts.append(f"Location '{expected_location}' created")
    else:
        feedback_parts.append(f"Location '{expected_location}' NOT found")

    # 3. Check Transfer Existence (20 pts)
    if len(transfers) > 0:
        score += 20
        feedback_parts.append("Transfer record created")
    else:
        feedback_parts.append("No transfer records found")

    # 4. Check Transfer Details (40 pts)
    # We look for at least one transfer that matches our criteria
    details_correct = False
    best_transfer_score = 0
    
    for t in transfers:
        t_score = 0
        
        # Check Item (10 pts)
        if expected_item.lower() in t.get("item_name", "").lower() or "chai" in str(t).lower():
            t_score += 10
            
        # Check Quantity (10 pts)
        qty = t.get("qty", 0)
        try:
            if float(qty) == float(expected_qty):
                t_score += 10
        except:
            pass
            
        # Check Date (10 pts)
        # Formats can vary, check for simple inclusion
        if expected_date in t.get("date", ""):
            t_score += 10
        elif "01/05/2026" in t.get("date", ""): # DD/MM/YYYY
            t_score += 10
            
        # Check Description (10 pts)
        if "showroom" in t.get("description", "").lower():
            t_score += 10
            
        if t_score > best_transfer_score:
            best_transfer_score = t_score
            
    score += best_transfer_score
    if best_transfer_score >= 30:
        feedback_parts.append("Transfer details mostly correct")
    elif best_transfer_score > 0:
        feedback_parts.append("Transfer details partially correct")
    else:
        if len(transfers) > 0:
             feedback_parts.append("Transfer details incorrect")

    passed = score >= 60 and location_found and len(transfers) > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }