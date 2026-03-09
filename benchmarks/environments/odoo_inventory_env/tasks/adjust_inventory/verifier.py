#!/usr/bin/env python3
"""
Verifier for Adjust Inventory task in Odoo Inventory

Verifies that an inventory adjustment was performed to set a product's quantity to 50 units.
Uses copy_from_env to read pre-exported verification data from the container.

Scoring (100 points total):
- Product quantity is exactly 50: 35 points
- Quantity changed from initial value: 25 points
- Adjustment was on the CORRECT TARGET product: 20 points
- Quantity in correct location: 10 points
- Reason/Reference provided ('Annual Stock Count'): 10 points
- Anti-gaming timestamp check: 5 points (reduced)

STRICT ANTI-GAMING:
- The adjustment MUST be on the TARGET product specified during setup
- Adjusting ANY OTHER product to 50 units gives ZERO credit
- No partial credit for adjusting wrong product

Pass threshold: 60 points with (quantity_is_50 AND correct_target_product AND reason_provided)
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_adjust_inventory(traj, env_info, task_info):
    """
    Verify that an inventory adjustment was performed correctly.

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
    target_quantity = float(metadata.get('target_quantity', 50))
    expected_keywords = metadata.get('expected_reason_keywords', ['annual', 'stock', 'count'])

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
        "quantity_is_50": False,
        "quantity_changed": False,
        "correct_target_product": False,  # RENAMED: Must be the CORRECT target product
        "correct_location": False,
        "reason_provided": False,
        "timestamp_check": False
    }

    # Extract data from result
    adjustment_found = result.get('adjustment_found', False)
    quantity_changed = result.get('quantity_changed', False)
    target_product = result.get('target_product', {})
    adjusted_product = result.get('adjusted_product', {})
    task_start = result.get('task_start_time', 0)
    task_end = result.get('task_end_time', 0)
    stock_location_id = result.get('stock_location_id', 0)

    logger.info(f"Result: adjustment_found={adjustment_found}, quantity_changed={quantity_changed}")
    logger.info(f"Target product: {target_product}")
    logger.info(f"Adjusted product: {adjusted_product}")

    # CRITICAL ANTI-GAMING CHECK: Verify adjusted product matches target product
    target_product_id = str(target_product.get('id', '')).strip()
    adjusted_product_id = str(adjusted_product.get('id', '')).strip()

    # The adjustment MUST be on the target product
    is_correct_product = False
    if target_product_id and adjusted_product_id:
        is_correct_product = (target_product_id == adjusted_product_id)
        if not is_correct_product:
            logger.warning(f"GAMING DETECTED: Adjusted product ID ({adjusted_product_id}) != Target product ID ({target_product_id})")
            feedback_parts.append(f"GAMING REJECTED: Adjusted wrong product (ID {adjusted_product_id}) instead of target (ID {target_product_id})")

    # Only use target_product for verification (never trust adjusted_product blindly)
    verify_product = target_product

    # ================================================================
    # CRITERION 1: Product quantity is exactly 50 (35 points)
    # ONLY counts if the TARGET product is at 50 (not any random product)
    # ================================================================
    current_qty = float(target_product.get('current_quantity', 0))

    # Check for exact match on TARGET product (with tolerance for floating point)
    if abs(current_qty - target_quantity) < 0.01:
        score += 35
        subscores["quantity_is_50"] = True
        feedback_parts.append(f"TARGET product quantity is exactly {target_quantity}")
    elif abs(current_qty - target_quantity) < 5:
        # Close to target - partial credit
        score += 20
        feedback_parts.append(f"TARGET product quantity is close: {current_qty} (expected: {target_quantity})")
    elif current_qty > 0:
        score += 5  # Some credit for having a quantity
        feedback_parts.append(f"TARGET product quantity is {current_qty} (expected: {target_quantity})")
    else:
        feedback_parts.append(f"TARGET product has no quantity found (expected: {target_quantity})")

    # ================================================================
    # CRITERION 2: TARGET product quantity changed from initial value (25 points)
    # ================================================================
    initial_qty = float(target_product.get('initial_quantity', 0))

    if initial_qty != current_qty and current_qty > 0:
        score += 25
        subscores["quantity_changed"] = True

        # Check direction of change
        if initial_qty < target_quantity and current_qty >= initial_qty:
            feedback_parts.append(f"TARGET product quantity increased: {initial_qty} -> {current_qty}")
        elif initial_qty > target_quantity and current_qty <= initial_qty:
            feedback_parts.append(f"TARGET product quantity decreased: {initial_qty} -> {current_qty}")
        else:
            feedback_parts.append(f"TARGET product quantity changed: {initial_qty} -> {current_qty}")
    elif adjustment_found and not is_correct_product:
        # NO credit for adjusting wrong product - this is gaming
        feedback_parts.append("GAMING REJECTED: Adjustment detected on DIFFERENT product - zero credit")
    else:
        feedback_parts.append("No quantity change detected on TARGET product")

    # ================================================================
    # CRITERION 3: Adjustment was on the CORRECT TARGET product (20 points)
    # This is the key anti-gaming criterion - adjusting wrong product = 0 points
    # ================================================================
    target_name = target_product.get('name', '')

    if is_correct_product and target_product_id:
        score += 20
        subscores["correct_target_product"] = True
        feedback_parts.append(f"Correct TARGET product adjusted: {target_name} (ID: {target_product_id})")
    elif target_product_id and not adjusted_product_id:
        # No adjustment detected at all
        feedback_parts.append(f"No adjustment detected on TARGET product: {target_name}")
    elif not is_correct_product and adjusted_product_id:
        # GAMING: Wrong product was adjusted
        wrong_name = adjusted_product.get('name', 'unknown')
        feedback_parts.append(f"GAMING REJECTED: Adjusted wrong product '{wrong_name}' instead of '{target_name}'")
    else:
        feedback_parts.append("Could not verify target product adjustment")

    # ================================================================
    # CRITERION 4: Quantity in correct location (10 points)
    # ================================================================
    if stock_location_id and int(stock_location_id) > 0:
        score += 10
        subscores["correct_location"] = True
        feedback_parts.append("Adjustment in correct stock location")
    else:
        feedback_parts.append("Stock location not verified")

    # ================================================================
    # CRITERION 5: Reason/Reference provided (10 points)
    # Task requires "Annual Stock Count" as reference
    # ================================================================
    adjustment_reason = result.get('adjustment_reason', '')
    reason_valid = result.get('reason_valid', False)

    if reason_valid:
        score += 10
        subscores["reason_provided"] = True
        feedback_parts.append(f"Adjustment reason contains expected keywords: {adjustment_reason}")
    elif adjustment_reason:
        # Has a reason but doesn't match expected keywords - no points
        feedback_parts.append(f"Adjustment reason provided but DOES NOT MATCH expected: '{adjustment_reason}' (expected keywords: annual, stock, count)")
    else:
        feedback_parts.append("No adjustment reason/reference provided (expected: 'Annual Stock Count')")

    # ================================================================
    # CRITERION 6: Timestamp anti-gaming check (5 points - reduced from 10)
    # ================================================================
    if task_start > 0 and task_end > 0:
        task_duration = task_end - task_start
        if task_duration > 20 and task_duration < 600:  # Between 20 sec and 10 min
            score += 5
            subscores["timestamp_check"] = True
            feedback_parts.append(f"Task completed in {task_duration}s (reasonable time)")
        elif task_duration >= 600:
            score += 2  # Partial credit
            feedback_parts.append(f"Task took {task_duration}s (very long)")
        else:
            feedback_parts.append(f"Task completed too quickly ({task_duration}s) - suspicious")
    else:
        feedback_parts.append("Timestamp data unavailable")

    # ================================================================
    # FINAL DETERMINATION
    # ================================================================
    # STRICT ANTI-GAMING: Must adjust the CORRECT TARGET product to 50 with reason
    key_criteria_met = (
        subscores["quantity_is_50"] and
        subscores["correct_target_product"] and  # MUST be the correct product
        subscores["reason_provided"]
    )

    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "target_quantity": target_quantity,
            "initial_quantity": initial_qty,
            "current_quantity": current_qty,
            "target_product_name": target_name,
            "target_product_id": target_product_id,
            "adjusted_product_id": adjusted_product_id,
            "is_correct_product": is_correct_product,
            "adjustment_found": adjustment_found,
            "adjustment_reason": result.get('adjustment_reason', ''),
            "score_breakdown": {
                "quantity_is_50": 35 if subscores["quantity_is_50"] else 0,
                "quantity_changed": 25 if subscores["quantity_changed"] else 0,
                "correct_target_product": 20 if subscores["correct_target_product"] else 0,
                "correct_location": 10 if subscores["correct_location"] else 0,
                "reason_provided": 10 if subscores["reason_provided"] else 0,
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
        "target_quantity": 50,
        "stock_location_id": 8,
        "initial_quant_count": 10,
        "current_quant_count": 10,
        "adjustment_found": True,
        "quantity_changed": True,
        "target_product": {
            "id": "5",
            "name": "Test Product",
            "initial_quantity": 25,
            "current_quantity": 50
        },
        "adjusted_product": {
            "id": "5",
            "name": "Test Product",
            "quantity": 50
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

    result = verify_adjust_inventory({}, env_info, task_info)
    print(f"Score: {result['score']}/100")
    print(f"Passed: {result['passed']}")
    print(f"Feedback: {result['feedback']}")
    print(f"Subscores: {result.get('subscores', {})}")
