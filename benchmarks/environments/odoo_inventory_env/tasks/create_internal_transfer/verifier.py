#!/usr/bin/env python3
"""
Verifier for Create Internal Transfer task in Odoo Inventory

Verifies that a new internal stock transfer was correctly created.
Uses copy_from_env to read pre-exported verification data from the container.

Scoring (100 points total):
- Transfer exists: 25 points
- Transfer is newly created: 20 points
- Transfer type is 'internal': 15 points
- Quantity meets minimum (10 units): 15 points
- Reference matches: 10 points
- Source and destination are different internal locations: 10 points
- Anti-gaming timestamp check: 5 points

STRICT ANTI-GAMING:
- Same-location transfers (source == destination) are INVALID and will FAIL
- An internal transfer MUST move goods between DIFFERENT locations

Pass threshold: 60 points with transfer_exists AND newly_created AND is_internal AND locations_valid
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_internal_transfer(traj, env_info, task_info):
    """
    Verify that an internal transfer was created correctly in Odoo Inventory.

    Uses copy_from_env to read the exported JSON result from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available from environment"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_reference = metadata.get('expected_reference', 'TRANSFER-001')
    min_quantity = float(metadata.get('min_quantity', 10))
    expected_type = metadata.get('expected_picking_type', 'internal')

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {
        "transfer_exists": False,
        "newly_created": False,
        "is_internal": False,
        "quantity_valid": False,
        "reference_match": False,
        "locations_valid": False,
        "timestamp_check": False
    }

    # Extract data from result
    transfer_found = result.get('transfer_found', False)
    newly_created = result.get('newly_created', False)
    transfer = result.get('transfer', {})
    validation = result.get('validation', {})
    task_start = result.get('task_start_time', 0)
    task_end = result.get('task_end_time', 0)
    initial_count = result.get('initial_picking_count', 0)
    current_count = result.get('current_picking_count', 0)

    logger.info(f"Result data: found={transfer_found}, newly_created={newly_created}")
    logger.info(f"Transfer: {transfer}")

    # ================================================================
    # CRITERION 1: Transfer exists (25 points)
    # ================================================================
    if transfer_found and transfer.get('id'):
        score += 25
        subscores["transfer_exists"] = True
        feedback_parts.append(f"Transfer found: {transfer.get('name', 'N/A')}")
    else:
        feedback_parts.append("No transfer found")

        # Check if count changed
        if current_count > initial_count:
            feedback_parts.append(f"Note: Picking count increased ({initial_count} -> {current_count}) but no matching transfer found")

        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # ================================================================
    # CRITERION 2: Transfer is newly created (20 points)
    # ================================================================
    if newly_created:
        score += 20
        subscores["newly_created"] = True
        feedback_parts.append("Transfer is newly created")
    elif current_count > initial_count:
        score += 10  # Partial credit
        subscores["newly_created"] = True
        feedback_parts.append("Picking count increased (new transfer likely)")
    else:
        feedback_parts.append("WARNING: Transfer may have existed before task")

    # ================================================================
    # CRITERION 3: Transfer type is 'internal' (15 points)
    # ================================================================
    picking_type = transfer.get('picking_type_code', '')
    is_internal = validation.get('is_internal', False)

    if is_internal or picking_type == expected_type:
        score += 15
        subscores["is_internal"] = True
        feedback_parts.append("Transfer type is 'internal' (correct)")
    elif picking_type:
        score += 5  # Partial credit for having a type
        feedback_parts.append(f"Transfer type is '{picking_type}' (expected: {expected_type})")
    else:
        feedback_parts.append("Transfer type not specified")

    # ================================================================
    # CRITERION 4: Quantity meets minimum (15 points)
    # ================================================================
    try:
        total_quantity = float(transfer.get('total_quantity', 0))
        quantity_valid = validation.get('quantity_valid', False)

        if quantity_valid or total_quantity >= min_quantity:
            score += 15
            subscores["quantity_valid"] = True
            feedback_parts.append(f"Quantity valid: {total_quantity} >= {min_quantity}")
        elif total_quantity > 0:
            # Partial credit for having some quantity
            partial_score = int(15 * (total_quantity / min_quantity))
            score += min(partial_score, 10)
            feedback_parts.append(f"Quantity partial: {total_quantity} < {min_quantity}")
        else:
            feedback_parts.append(f"No quantity specified (expected >= {min_quantity})")
    except (ValueError, TypeError):
        feedback_parts.append("Invalid quantity value")

    # ================================================================
    # CRITERION 5: Reference matches EXACTLY (10 points)
    # ================================================================
    transfer_ref = transfer.get('reference', '') or ''
    transfer_name = transfer.get('name', '') or ''

    # EXACT match only - no substring matching allowed (anti-gaming)
    if transfer_ref.lower().strip() == expected_reference.lower().strip():
        score += 10
        subscores["reference_match"] = True
        feedback_parts.append(f"Reference matches exactly: {transfer_ref}")
    elif transfer_ref or transfer_name:
        # No partial credit for having a reference that doesn't match
        feedback_parts.append(f"Reference DOES NOT MATCH: '{transfer_ref}' (expected exactly: '{expected_reference}')")
    else:
        feedback_parts.append("No reference/origin set")

    # ================================================================
    # CRITERION 6: Source and destination are different (10 points)
    # THIS IS A KEY CRITERION - same-location transfers are INVALID
    # ================================================================
    source_loc = transfer.get('source_location', '')
    dest_loc = transfer.get('dest_location', '')

    if source_loc and dest_loc:
        if source_loc != dest_loc:
            score += 10
            subscores["locations_valid"] = True
            feedback_parts.append(f"Locations valid: {source_loc} -> {dest_loc}")
        else:
            # CRITICAL: Same-location transfer is INVALID - this fails the task
            feedback_parts.append(f"INVALID TRANSFER: Source and destination are the SAME ({source_loc}) - cannot move goods to same location")
    else:
        feedback_parts.append("Source or destination location not set")

    # ================================================================
    # CRITERION 7: Timestamp anti-gaming check (5 points)
    # ================================================================
    if task_start > 0 and task_end > 0:
        task_duration = task_end - task_start
        if task_duration > 15 and task_duration < 600:  # Between 15 sec and 10 min
            score += 5
            subscores["timestamp_check"] = True
            feedback_parts.append(f"Task completed in {task_duration}s (reasonable time)")
        elif task_duration >= 600:
            score += 3  # Partial credit
            feedback_parts.append(f"Task took {task_duration}s (very long)")
        else:
            feedback_parts.append(f"Task completed too quickly ({task_duration}s) - suspicious")
    else:
        feedback_parts.append("Timestamp data unavailable")

    # ================================================================
    # FINAL DETERMINATION
    # ================================================================
    # STRICT: Must have valid transfer with DIFFERENT locations
    # Same-location transfers are meaningless and indicate gaming
    key_criteria_met = (
        subscores["transfer_exists"] and
        subscores["newly_created"] and
        subscores["is_internal"] and
        subscores["locations_valid"]  # CRITICAL: Must have different source/destination
    )

    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "expected_type": expected_type,
            "expected_reference": expected_reference,
            "min_quantity": min_quantity,
            "transfer_id": transfer.get('id', 'N/A'),
            "transfer_name": transfer.get('name', 'N/A'),
            "transfer_state": transfer.get('state', 'N/A'),
            "total_quantity": transfer.get('total_quantity', 'N/A'),
            "source_location": transfer.get('source_location', 'N/A'),
            "dest_location": transfer.get('dest_location', 'N/A'),
            "score_breakdown": {
                "transfer_exists": 25 if subscores["transfer_exists"] else 0,
                "newly_created": 20 if subscores["newly_created"] else 0,
                "is_internal": 15 if subscores["is_internal"] else 0,
                "quantity_valid": 15 if subscores["quantity_valid"] else 0,
                "reference_match": 10 if subscores["reference_match"] else 0,
                "locations_valid": 10 if subscores["locations_valid"] else 0,
                "timestamp_check": 5 if subscores["timestamp_check"] else 0
            }
        }
    }


# For local testing
if __name__ == "__main__":
    # Mock test
    test_result = {
        "task_start_time": 1700000000,
        "task_end_time": 1700000180,
        "initial_picking_count": 5,
        "current_picking_count": 6,
        "max_picking_id_before": 5,
        "transfer_found": True,
        "newly_created": True,
        "transfer": {
            "id": "6",
            "name": "WH/INT/00001",
            "reference": "TRANSFER-001",
            "state": "draft",
            "picking_type_code": "internal",
            "source_location": "WH/Stock",
            "dest_location": "WH/Stock/Shelf 1",
            "total_quantity": 10,
            "product_name": "Test Product"
        },
        "validation": {
            "is_internal": True,
            "quantity_valid": True
        }
    }

    # Write test result
    import tempfile
    import shutil

    with open("/tmp/test_result.json", "w") as f:
        json.dump(test_result, f)

    def test_copy(src, dst):
        shutil.copy("/tmp/test_result.json", dst)

    env_info = {"copy_from_env": test_copy}
    task_info = {"metadata": {}}

    result = verify_create_internal_transfer({}, env_info, task_info)
    print(f"Score: {result['score']}/100")
    print(f"Passed: {result['passed']}")
    print(f"Feedback: {result['feedback']}")
    print(f"Subscores: {result.get('subscores', {})}")
