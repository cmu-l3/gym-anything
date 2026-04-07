#!/usr/bin/env python3
"""Verifier for update_inventory_stock_levels task."""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_inventory_stock_levels(traj, env_info, task_info):
    """
    Verify that the agent updated the correct chemical quantities 
    and left others untouched.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_updates = metadata.get('expected_updates', {
        'ethanol absolute': 850.0,
        'acetone': 125.5,
        'toluene': 210.0
    })
    control_item = metadata.get('control_item', {'methanol': 2000.0})

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

    items = result.get('items', [])
    task_start = float(result.get('task_start', 0))

    # Build a case-insensitive lookup map
    item_map = {item['name'].strip().lower(): item for item in items if isinstance(item, dict) and 'name' in item}

    score = 0
    feedback_parts = []

    if not items:
        return {"passed": False, "score": 0, "feedback": "Inventory data empty or not found. Target inventory may have been deleted."}

    # Evaluate targeted updates (30 points each)
    for name, expected_val in expected_updates.items():
        if name in item_map:
            try:
                # Handle possible string formatting
                val_str = str(item_map[name].get('value', ''))
                # Strip out any non-numeric characters besides decimal point just in case they typed "850 mL"
                clean_val_str = ''.join(c for c in val_str if c.isdigit() or c == '.')
                val = float(clean_val_str)
                updated_at = float(item_map[name].get('updated_at', 0))

                if abs(val - expected_val) < 0.1:
                    # Check anti-gaming timestamp
                    if updated_at > task_start:
                        score += 30
                        feedback_parts.append(f"{name.title()} correctly updated to {val}")
                    else:
                        score += 15
                        feedback_parts.append(f"{name.title()} has correct value but appears unchanged (timestamp is old)")
                else:
                    feedback_parts.append(f"{name.title()} value incorrect (Expected: {expected_val}, Got: {val})")
            except ValueError:
                feedback_parts.append(f"{name.title()} has invalid or missing numerical value")
        else:
            feedback_parts.append(f"{name.title()} missing from inventory")

    # Evaluate control item (10 points)
    for name, expected_val in control_item.items():
        if name in item_map:
            try:
                val_str = str(item_map[name].get('value', ''))
                clean_val_str = ''.join(c for c in val_str if c.isdigit() or c == '.')
                val = float(clean_val_str)

                if abs(val - expected_val) < 0.1:
                    score += 10
                    feedback_parts.append(f"{name.title()} (Control) safely unchanged")
                else:
                    feedback_parts.append(f"WARNING: {name.title()} was improperly modified to {val}")
            except ValueError:
                feedback_parts.append(f"{name.title()} has corrupted value")
        else:
            feedback_parts.append(f"{name.title()} missing from inventory")

    # Pass if all intended edits were successfully made
    passed = score >= 90

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }