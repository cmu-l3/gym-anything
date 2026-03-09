#!/usr/bin/env python3
"""
Verifier for configure_inventory_tracking task.
Verifies that:
1. A menu item "Surf and Turf" exists.
2. Price is 45.00.
3. Stock/Inventory is set to 12.
"""

import json
import os
import re
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_inventory_tracking(traj, env_info, task_info):
    """
    Verify the menu item creation and inventory configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the DB query result text file
    temp_db_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/menu_item_query_result.txt", temp_db_file.name)
        with open(temp_db_file.name, 'r', encoding='utf-8', errors='ignore') as f:
            db_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve DB records: {e}"}
    finally:
        if os.path.exists(temp_db_file.name):
            os.unlink(temp_db_file.name)

    # 2. Retrieve the general task result JSON
    temp_json_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json_file.name)
        with open(temp_json_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception:
        task_result = {}
    finally:
        if os.path.exists(temp_json_file.name):
            os.unlink(temp_json_file.name)

    score = 0
    feedback_parts = []
    
    # Parse DB Content
    # Expected format from Derby ij:
    # NAME | PRICE | STOCK_AMOUNT | ...
    # Surf and Turf | 45.0 | 12 | ...
    
    # Check 1: Item Creation (30 pts)
    # We look for "Surf and Turf" (case insensitive)
    item_found = False
    if re.search(r"Surf\s+and\s+Turf", db_content, re.IGNORECASE):
        score += 30
        item_found = True
        feedback_parts.append("Item 'Surf and Turf' found in database.")
    else:
        feedback_parts.append("Item 'Surf and Turf' NOT found in database.")

    # Check 2: Price Configuration (20 pts)
    # Look for 45.0 or 45.00 near the name
    price_correct = False
    if item_found:
        # Regex to find row with Surf and Turf and 45.0
        # This is loose matching to handle variable whitespace in table output
        if re.search(r"Surf\s+and\s+Turf.*45\.0", db_content, re.IGNORECASE | re.DOTALL):
            score += 20
            price_correct = True
            feedback_parts.append("Price set correctly to 45.00.")
        else:
            feedback_parts.append("Price is incorrect (expected 45.00).")

    # Check 3: Inventory/Stock Configuration (40 pts)
    # Look for stock amount '12'
    # Note: Column order in query was NAME, PRICE, STOCK_AMOUNT
    # So 12 should appear after 45.0
    stock_correct = False
    if item_found:
        # We look for the number 12 appearing after the name
        # Depending on column width, it might be separated by spaces or pipes
        if re.search(r"Surf\s+and\s+Turf.*(?:45\.0|45).*12(?:\.0)?\b", db_content, re.IGNORECASE | re.DOTALL):
            score += 40
            stock_correct = True
            feedback_parts.append("Inventory stock set correctly to 12.")
        else:
            feedback_parts.append("Inventory stock is incorrect (expected 12).")

    # Check 4: App State (10 pts)
    if task_result.get("app_was_running", False):
        score += 10
    else:
        feedback_parts.append("Application was not running at end of task.")

    # Pass logic
    passed = (score >= 90) # Requires Name, Price, and Stock to be correct (30+20+40 = 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }