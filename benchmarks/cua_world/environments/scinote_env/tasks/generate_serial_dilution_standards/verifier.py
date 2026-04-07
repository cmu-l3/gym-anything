#!/usr/bin/env python3
"""Verifier for generate_serial_dilution_standards task."""

import json
import tempfile
import os

def verify_serial_dilution_standards(traj, env_info, task_info):
    """Verify that the inventory and the 5 specific standard curve items were created."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_inventory = metadata.get('expected_inventory_name', 'BCA Assay Standards')
    expected_items = metadata.get('expected_items', [])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/serial_dilution_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    initial_repo_count = int(result.get('initial_repository_count', 0))
    current_repo_count = int(result.get('current_repository_count', 0))
    initial_row_count = int(result.get('initial_row_count', 0))
    current_row_count = int(result.get('current_row_count', 0))

    repo_found = result.get('repository_found', False)
    repository = result.get('repository', {})
    item_count = int(result.get('item_count', 0))
    items = result.get('items', [])

    # Anti-gaming check: Make sure rows were actually added during this session
    if current_row_count <= initial_row_count:
        feedback_parts.append(f"No new items were created during this session (Initial: {initial_row_count}, Current: {current_row_count}).")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 1 (20 pts): Inventory exists with exact name
    if repo_found:
        actual_name = repository.get('name', '')
        if actual_name.strip().lower() == expected_inventory.lower():
            score += 20
            feedback_parts.append(f"Inventory '{expected_inventory}' found")
        else:
            feedback_parts.append(f"Inventory name mismatch: expected '{expected_inventory}', got '{actual_name}'")
    else:
        feedback_parts.append(f"Inventory '{expected_inventory}' not found")
        # Can't evaluate items if the repository wasn't found
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2 (20 pts): Exactly 5 items in the repository
    if item_count == 5:
        score += 20
        feedback_parts.append("Exactly 5 items found in the inventory")
    elif item_count > 0:
        score += 10
        feedback_parts.append(f"Found {item_count} items in the inventory, expected exactly 5")
    else:
        feedback_parts.append("No items found in the inventory")

    # Criterion 3 (12 pts each, 60 total): Specific items exist
    def check_item(letter, concentration):
        for item in items:
            item_lower = item.lower().replace('µ', 'u')  # Normalize mu
            # Check for the letter designation AND the concentration value
            if f"std {letter.lower()}" in item_lower and str(concentration) in item_lower:
                return True
        return False

    items_found = 0
    for exp in expected_items:
        letter = exp["letter"]
        conc = exp["concentration"]
        
        if check_item(letter, conc):
            score += 12
            items_found += 1
            feedback_parts.append(f"Item 'Std {letter}' ({conc} ug/mL) found")
        else:
            feedback_parts.append(f"Item 'Std {letter}' ({conc} ug/mL) missing or improperly named")

    # The task passes if the repo is created and at least 4 items are perfectly matched (Score >= 88)
    # Threshold is exactly 80 as defined in task strategy.
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "inventory_created": repo_found,
            "correct_item_count": item_count == 5,
            "specific_items_found": items_found
        }
    }