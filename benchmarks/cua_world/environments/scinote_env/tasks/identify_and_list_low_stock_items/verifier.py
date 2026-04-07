#!/usr/bin/env python3
"""Verifier for identify_and_list_low_stock_items task."""

import json
import tempfile
import os

def verify_low_stock_requisition(traj, env_info, task_info):
    """Verify that the correct low stock items were tagged and compiled into the new task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Obtain Ground Truth expectations
    metadata = task_info.get('metadata', {})
    low_stock_keywords = metadata.get('low_stock', ["Acetone", "Methanol", "DMSO", "Hexane"])
    high_stock_keywords = metadata.get('high_stock', ["Ethanol", "PBS Buffer", "Chloroform", "Deionized Water"])
    expected_task_name = metadata.get('expected_task_name', 'Weekly Requisition')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Parse exported results
    tagged_items = [t.lower() for t in result.get('tagged', [])]
    task_found = result.get('task_found', False)
    task_name = result.get('task_name', '').lower()
    task_text = result.get('task_text', '').lower()

    # Criterion 1: Low-stock items successfully tagged (30 pts)
    tagged_low_stock_count = 0
    for keyword in low_stock_keywords:
        if any(keyword.lower() in t for t in tagged_items):
            tagged_low_stock_count += 1
    
    if tagged_low_stock_count > 0:
        pts = int((tagged_low_stock_count / len(low_stock_keywords)) * 30)
        score += pts
        feedback_parts.append(f"Tagged {tagged_low_stock_count}/{len(low_stock_keywords)} low-stock items (+{pts})")
    else:
        feedback_parts.append("No low-stock items were correctly tagged")

    # Criterion 2: High-stock items accurately untagged (20 pts)
    wrongly_tagged_count = 0
    for keyword in high_stock_keywords:
        if any(keyword.lower() in t for t in tagged_items):
            wrongly_tagged_count += 1
    
    if wrongly_tagged_count == 0 and tagged_low_stock_count > 0:
        score += 20
        feedback_parts.append("No high-stock items were incorrectly tagged (+20)")
    elif wrongly_tagged_count > 0:
        feedback_parts.append(f"Incorrectly tagged {wrongly_tagged_count} high-stock items")
    else:
        feedback_parts.append("No items were tagged at all")

    # Criterion 3: Requisition Task created in the Experiment (10 pts)
    if task_found and expected_task_name.lower() in task_name:
        score += 10
        feedback_parts.append(f"Task '{expected_task_name}' found (+10)")
    elif task_found:
        score += 5
        feedback_parts.append(f"Task created but with an inaccurate name ('{task_name}') (+5)")
    else:
        feedback_parts.append("Requisition task was not found")

    # Criterion 4: Chemical names are documented in the Task Description/Steps (40 pts)
    listed_items_count = 0
    for keyword in low_stock_keywords:
        if keyword.lower() in task_text:
            listed_items_count += 1
    
    if listed_items_count > 0:
        pts = int((listed_items_count / len(low_stock_keywords)) * 40)
        score += pts
        feedback_parts.append(f"Compiled {listed_items_count}/{len(low_stock_keywords)} low-stock chemicals into task notes (+{pts})")
    else:
        feedback_parts.append("Failed to list the target chemicals in the task text/description")

    # Pass logic: Requires reasonably solid completion of both core goals (tagging & listing)
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "low_stock_tagged_count": tagged_low_stock_count,
            "false_positives_count": wrongly_tagged_count,
            "task_creation": task_found,
            "chemicals_listed_count": listed_items_count
        }
    }