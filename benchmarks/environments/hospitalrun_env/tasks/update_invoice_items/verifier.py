#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_invoice(traj, env_info, task_info):
    """
    Verifies that the agent added the 'Urinalysis' item to the specific invoice.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    added_item_name = metadata.get('added_item_name', 'Urinalysis')
    expected_total = float(metadata.get('expected_total', 75.00))

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    invoice_data = result.get('invoice_data', {})
    
    # 1. Basic Existence Check
    if not invoice_data.get('exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target invoice document INV-2024-001 was deleted or not found."
        }

    score = 0
    feedback = []

    # 2. Check Modification (Anti-gaming)
    # The document revision should have changed from the initial setup
    if invoice_data.get('modified'):
        score += 20
        feedback.append("Invoice was modified.")
    else:
        feedback.append("Invoice was NOT modified (revision matches initial state).")
        # If not modified, they certainly didn't add the item
        return {"passed": False, "score": 0, "feedback": "Task failed: No changes made to the invoice."}

    # 3. Check Item Count
    # Should be 2 items (Consultation + Urinalysis)
    item_count = invoice_data.get('item_count', 0)
    if item_count == 2:
        score += 30
        feedback.append("Correct number of line items (2).")
    elif item_count > 2:
        score += 10
        feedback.append(f"Too many line items found ({item_count}).")
    else:
        feedback.append(f"Insufficient line items found ({item_count}).")

    # 4. Check Specific Item Content
    item_names = [name.lower() for name in invoice_data.get('item_names', [])]
    target_found = any(added_item_name.lower() in name for name in item_names)
    
    if target_found:
        score += 30
        feedback.append(f"Found added item: '{added_item_name}'.")
    else:
        feedback.append(f"Missing item: '{added_item_name}' not found in {invoice_data.get('item_names')}.")

    # 5. Check Totals
    # Allow small float tolerance
    actual_total = float(invoice_data.get('total', 0))
    if abs(actual_total - expected_total) < 0.01:
        score += 20
        feedback.append(f"Total amount is correct (${actual_total}).")
    else:
        feedback.append(f"Total amount incorrect. Expected ${expected_total}, got ${actual_total}.")

    # Pass logic
    # Must have modified doc, found the specific item, and have correct count
    passed = (invoice_data.get('modified') and target_found and item_count == 2)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }