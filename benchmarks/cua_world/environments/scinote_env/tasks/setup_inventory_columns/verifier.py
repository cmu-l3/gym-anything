#!/usr/bin/env python3
"""Verifier for setup_inventory_columns task."""

import json
import tempfile
import os


def verify_setup_inventory_columns(traj, env_info, task_info):
    """Verify inventory with custom column and populated items."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_inventory = metadata.get('expected_inventory_name', 'Antibody Stock')
    expected_column = metadata.get('expected_column_name', 'Catalog Number')
    expected_items = metadata.get('expected_items', [
        {"name": "Anti-CD3 mAb", "catalog_number": "AB-10042"},
        {"name": "Anti-CD8 mAb", "catalog_number": "AB-20078"}
    ])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/setup_inventory_columns_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    repo_found = result.get('repository_found', False)
    repository = result.get('repository', {})
    columns = result.get('columns', [])
    items = result.get('items', [])

    # Criterion 1 (15 pts): Inventory exists with correct name
    inventory_ok = False
    if repo_found:
        actual_name = repository.get('name', '')
        if actual_name.strip().lower() == expected_inventory.strip().lower():
            inventory_ok = True
            score += 15
            feedback_parts.append(f"Inventory '{expected_inventory}' found")
        else:
            feedback_parts.append(f"Inventory name mismatch: '{actual_name}'")
    else:
        feedback_parts.append(f"Inventory '{expected_inventory}' not found")

    # Criterion 2 (15 pts): Custom text column exists
    column_ok = False
    col_names = [c.get('name', '').strip().lower() for c in columns]
    if expected_column.strip().lower() in col_names:
        column_ok = True
        score += 15
        feedback_parts.append(f"Column '{expected_column}' found")
    else:
        feedback_parts.append(f"Column '{expected_column}' not found (columns: {col_names})")

    # Build item lookup
    item_lookup = {}
    for it in items:
        name = it.get('name', '').strip().lower()
        item_lookup[name] = it

    # Criterion 3-6: Check each expected item (name + catalog number)
    # 2 items x (name=15pts + catalog=10pts) = 50pts total
    items_found = 0
    catalogs_found = 0
    for exp_item in expected_items:
        exp_name = exp_item['name']
        exp_catalog = exp_item['catalog_number']

        if exp_name.strip().lower() in item_lookup:
            items_found += 1
            score += 15
            feedback_parts.append(f"Item '{exp_name}' found")

            actual_catalog = item_lookup[exp_name.strip().lower()].get('catalog_number', '')
            if actual_catalog.strip() == exp_catalog.strip():
                catalogs_found += 1
                score += 10
                feedback_parts.append(f"Catalog '{exp_catalog}' correct for '{exp_name}'")
            elif actual_catalog.strip():
                score += 5  # partial: has a catalog value but wrong
                feedback_parts.append(f"Catalog mismatch for '{exp_name}': expected '{exp_catalog}', got '{actual_catalog}'")
            else:
                feedback_parts.append(f"No catalog number set for '{exp_name}'")
        else:
            feedback_parts.append(f"Item '{exp_name}' not found")

    # All criteria must be met: inventory, column, both items with catalogs
    passed = inventory_ok and column_ok and items_found == len(expected_items) and catalogs_found == len(expected_items)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "inventory_found": inventory_ok,
            "custom_column_exists": column_ok,
            "items_found": items_found,
            "catalogs_correct": catalogs_found
        }
    }
