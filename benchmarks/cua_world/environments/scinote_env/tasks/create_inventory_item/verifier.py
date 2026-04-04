#!/usr/bin/env python3
"""Verifier for create_inventory_item task."""

import json
import tempfile
import os


def verify_create_inventory_item(traj, env_info, task_info):
    """Verify that a new inventory was created and an item was added to it."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_inventory = metadata.get('expected_inventory_name', 'Lab Reagents')
    expected_item = metadata.get('expected_item_name', 'Tris-HCl Buffer pH 7.4')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_inventory_result.json", temp_file.name)
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
    item_found = result.get('item_found', False)
    item = result.get('item', {})

    # Criterion 1 (35 pts): Inventory (repository) with expected name exists
    inventory_name_ok = False
    if repo_found:
        actual_name = repository.get('name', '')
        if actual_name.strip().lower() == expected_inventory.strip().lower():
            inventory_name_ok = True
            score += 35
            feedback_parts.append(f"Inventory '{expected_inventory}' found")
        else:
            feedback_parts.append(f"Inventory name mismatch: expected '{expected_inventory}', got '{actual_name}'")
    else:
        feedback_parts.append(f"Inventory '{expected_inventory}' not found")

    # Criterion 2 (15 pts): Repository count increased
    if current_repo_count > initial_repo_count:
        score += 15
        feedback_parts.append(f"Inventory count increased ({initial_repo_count} -> {current_repo_count})")
    else:
        feedback_parts.append(f"Inventory count unchanged ({initial_repo_count} -> {current_repo_count})")

    # Criterion 3 (35 pts): Item with expected name exists
    item_name_ok = False
    if item_found:
        actual_item_name = item.get('name', '')
        if actual_item_name.strip().lower() == expected_item.strip().lower():
            item_name_ok = True
            score += 35
            feedback_parts.append(f"Item '{expected_item}' found")
        else:
            feedback_parts.append(f"Item name mismatch: expected '{expected_item}', got '{actual_item_name}'")
    else:
        feedback_parts.append(f"Item '{expected_item}' not found")

    # Criterion 4 (15 pts): Row count increased
    if current_row_count > initial_row_count:
        score += 15
        feedback_parts.append(f"Row count increased ({initial_row_count} -> {current_row_count})")
    else:
        feedback_parts.append(f"Row count unchanged ({initial_row_count} -> {current_row_count})")

    # Must have both name matches to pass (both objectives completed)
    passed = inventory_name_ok and item_name_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "inventory_name_match": repo_found and repository.get('name', '').strip().lower() == expected_inventory.strip().lower(),
            "inventory_count_increased": current_repo_count > initial_repo_count,
            "item_name_match": item_found and item.get('name', '').strip().lower() == expected_item.strip().lower(),
            "row_count_increased": current_row_count > initial_row_count
        }
    }
