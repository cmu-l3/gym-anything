#!/usr/bin/env python3
"""
Verifier for update_service_price task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_service_price(traj, env_info, task_info):
    """
    Verifies that the agent updated the specific pricing item correctly.
    
    Criteria:
    1. The original document ID must still exist (not deleted).
    2. The Name must be 'Standard GP Consultation'.
    3. The Price must be 60.00.
    4. The document revision must have changed (proof of update).
    5. No duplicate items with the same name should exist (clean update).
    """
    
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: Copy function missing"}

    metadata = task_info.get("metadata", {})
    expected_name = metadata.get("expected_name", "Standard GP Consultation")
    expected_price = float(metadata.get("expected_price", 60.00))

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    target_doc = result.get('target_doc', {})
    duplicates = result.get('duplicates', [])
    initial_rev = result.get('initial_rev', "")
    
    exists = target_doc.get('exists', False)
    actual_name = target_doc.get('name', "")
    actual_price = target_doc.get('price', 0)
    current_rev = target_doc.get('rev', "")

    score = 0
    feedback = []

    # 3. Scoring Logic

    # Criterion A: Document Persistence (20 pts)
    # The original document ID must still exist. If the agent deleted it and created new, this fails.
    if exists:
        score += 20
        feedback.append("Original document ID preserved.")
    else:
        feedback.append("Original document was deleted.")
        # If deleted, we check if they created a new one (duplicates) to give partial credit later
        # But for now, major penalty.

    # Criterion B: Name Update (30 pts)
    name_correct = False
    if exists and actual_name and actual_name.strip().lower() == expected_name.lower():
        score += 30
        name_correct = True
        feedback.append(f"Name updated correctly to '{actual_name}'.")
    elif exists:
        feedback.append(f"Name mismatch: Expected '{expected_name}', got '{actual_name}'.")

    # Criterion C: Price Update (30 pts)
    price_correct = False
    try:
        # Handle string or float price
        p_val = float(actual_price)
        if abs(p_val - expected_price) < 0.01:
            score += 30
            price_correct = True
            feedback.append(f"Price updated correctly to {p_val}.")
        elif exists:
            feedback.append(f"Price mismatch: Expected {expected_price}, got {p_val}.")
    except (ValueError, TypeError):
        if exists:
            feedback.append(f"Invalid price format: {actual_price}")

    # Criterion D: Modification Check (10 pts)
    # Rev must be different from initial
    if exists and current_rev != initial_rev:
        score += 10
        feedback.append("Document version incremented (update confirmed).")
    elif exists:
        feedback.append("Document version unchanged (no changes saved?).")

    # Criterion E: Duplicate Check (10 pts)
    # If the agent created a NEW item with the right name instead of updating, duplicates will be > 0.
    if len(duplicates) == 0:
        score += 10
        feedback.append("No duplicate records created.")
    else:
        feedback.append(f"Found {len(duplicates)} duplicate/new records with the same name. Should have updated the existing one.")
        # Penalty: If they deleted original and created new, score is currently low.
        # We can give partial credit here if original is gone but new one exists.
        if not exists and len(duplicates) > 0:
            score += 30 # Partial credit for achieving the end state via wrong method
            feedback.append("Partial credit: Created new record instead of updating existing.")

    # Final Pass Check
    # Must have preserved ID, name correct, price correct to pass fully.
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }