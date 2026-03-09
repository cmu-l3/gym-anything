#!/usr/bin/env python3
"""Verifier for create_collection_organize task."""

import json
import tempfile
import os

def verify_create_collection_organize(traj, env_info, task_info):
    """Verify that collection was created and RIS file was imported into it."""

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    collection_name = metadata.get('collection_name', 'Machine Learning Papers')
    expected_min_items = metadata.get('expected_min_items', 7)
    expected_max_items = metadata.get('expected_max_items', 9)

    # Copy result file from container
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

    # Evaluate results
    score = 0
    feedback_parts = []

    collections_added = result.get('collections_added', 0)
    items_added = result.get('items_added', 0)
    collection_found = result.get('collection_found', False)
    items_in_collection = result.get('items_in_collection', 0)

    # Criterion 1: Collection was created (25 points)
    if collections_added > 0:
        score += 15
        feedback_parts.append(f"Collection created ({collections_added} new)")
    else:
        feedback_parts.append("No collection created")

    # Criterion 2: Specific collection found (25 points)
    if collection_found == "true" or str(collection_found).lower() == "true":
        score += 25
        feedback_parts.append(f"Collection '{collection_name}' found")
    else:
        feedback_parts.append(f"Collection '{collection_name}' not found")

    # Criterion 3: Items were imported (20 points)
    if items_added > 0:
        score += 20
        feedback_parts.append(f"Items imported ({items_added} total added)")
    else:
        feedback_parts.append("No items imported")

    # Criterion 4: Items are in the collection (30 points)
    if expected_min_items <= items_in_collection <= expected_max_items:
        score += 30
        feedback_parts.append(f"Correct items in collection ({items_in_collection})")
    elif items_in_collection > 0:
        partial_score = int(30 * min(items_in_collection, expected_min_items) / expected_min_items)
        score += partial_score
        feedback_parts.append(f"Some items in collection ({items_in_collection}, expected {expected_min_items}-{expected_max_items})")
    else:
        feedback_parts.append("No items in collection")

    # Task passes if score >= 60
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "collections_added": collections_added,
            "items_in_collection": items_in_collection,
            "collection_found": collection_found
        }
    }
