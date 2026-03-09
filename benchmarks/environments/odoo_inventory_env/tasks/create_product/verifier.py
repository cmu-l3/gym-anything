#!/usr/bin/env python3
"""
Verifier for Create Product task in Odoo Inventory

Verifies that a new storable product was correctly created with the specified details.
Uses copy_from_env to read pre-exported verification data from the container.

Scoring (100 points total):
- Product exists with correct name: 25 points
- Product is newly created (not pre-existing): 20 points
- Product type is 'storable' (product): 15 points
- Internal reference matches: 10 points
- Barcode matches: 10 points
- Sales price within tolerance: 10 points
- Cost within tolerance: 5 points
- Anti-gaming timestamp check: 5 points

Pass threshold: 65 points with product_exists AND newly_created AND correct_type
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_product(traj, env_info, task_info):
    """
    Verify that a product was created correctly in Odoo Inventory.

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
    expected_name = metadata.get('expected_product_name', 'Industrial Safety Helmet')
    expected_type = metadata.get('expected_product_type', 'product')
    expected_ref = metadata.get('expected_internal_ref', 'HELM-IND-001')
    expected_barcode = metadata.get('expected_barcode', '5901234123457')
    expected_price = float(metadata.get('expected_sales_price', 45.00))
    expected_cost = float(metadata.get('expected_cost', 28.00))

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
        "product_exists": False,
        "newly_created": False,
        "correct_type": False,
        "name_match": False,
        "ref_match": False,
        "barcode_match": False,
        "price_match": False,
        "cost_match": False,
        "timestamp_check": False
    }

    # Extract data from result
    product_found = result.get('product_found', False)
    newly_created = result.get('newly_created', False)
    product = result.get('product', {})
    validation = result.get('validation', {})
    task_start = result.get('task_start_time', 0)
    task_end = result.get('task_end_time', 0)
    initial_count = result.get('initial_product_count', 0)
    current_count = result.get('current_product_count', 0)

    logger.info(f"Result data: found={product_found}, newly_created={newly_created}")
    logger.info(f"Product: {product}")

    # ================================================================
    # CRITERION 1: Product exists with EXACT matching name (25 points)
    # ================================================================
    if product_found:
        product_name = product.get('name', '').lower().strip()
        expected_name_lower = expected_name.lower().strip()

        # EXACT match only - no substring/partial matches allowed
        if product_name == expected_name_lower:
            score += 25
            subscores["product_exists"] = True
            subscores["name_match"] = True
            feedback_parts.append(f"Product found: '{product.get('name')}'")
        else:
            # No points for wrong product name
            feedback_parts.append(f"Product found but name DOES NOT MATCH: '{product.get('name')}' (expected EXACTLY: '{expected_name}')")
    else:
        feedback_parts.append(f"No product found matching '{expected_name}'")

        # Check if count changed at all
        if current_count > initial_count:
            feedback_parts.append(f"Note: Product count increased ({initial_count} -> {current_count}) but target product not found")

        # Early return - nothing else to verify
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # ================================================================
    # CRITERION 2: Newly created during task (20 points)
    # ================================================================
    if newly_created:
        score += 20
        subscores["newly_created"] = True
        feedback_parts.append("Product is newly created during task")
    elif current_count > initial_count:
        score += 10  # Partial credit - count increased
        subscores["newly_created"] = True
        feedback_parts.append("Product count increased (new product likely created)")
    else:
        feedback_parts.append("WARNING: Product may have existed before task")

    # ================================================================
    # CRITERION 3: Product type is 'storable' (15 points)
    # ================================================================
    product_type = product.get('type', '')
    type_valid = validation.get('type_valid', False)

    if type_valid or product_type == expected_type:
        score += 15
        subscores["correct_type"] = True
        feedback_parts.append("Product type is 'Storable' (correct)")
    elif product_type == 'consu':
        score += 5  # Partial credit for consumable
        feedback_parts.append(f"Product type is 'Consumable' (expected: Storable)")
    elif product_type:
        feedback_parts.append(f"Product type is '{product_type}' (expected: {expected_type})")
    else:
        feedback_parts.append("Product type not specified")

    # ================================================================
    # CRITERION 4: Internal reference matches EXACTLY (10 points)
    # ================================================================
    product_ref = product.get('internal_reference', '')
    if product_ref == expected_ref:
        score += 10
        subscores["ref_match"] = True
        feedback_parts.append(f"Internal reference matches: {product_ref}")
    elif product_ref:
        # No partial credit - must be exact match
        feedback_parts.append(f"Internal reference DOES NOT MATCH: '{product_ref}' (expected: '{expected_ref}')")
    else:
        feedback_parts.append("No internal reference set")

    # ================================================================
    # CRITERION 5: Barcode matches EXACTLY (10 points)
    # ================================================================
    product_barcode = product.get('barcode', '')
    if product_barcode == expected_barcode:
        score += 10
        subscores["barcode_match"] = True
        feedback_parts.append(f"Barcode matches: {product_barcode}")
    elif product_barcode:
        # No partial credit - must be exact match
        feedback_parts.append(f"Barcode DOES NOT MATCH: '{product_barcode}' (expected: '{expected_barcode}')")
    else:
        feedback_parts.append("No barcode set")

    # ================================================================
    # CRITERION 6: Sales price within tolerance (10 points)
    # ================================================================
    try:
        actual_price = float(product.get('sales_price', 0))
        price_tolerance = expected_price * 0.05  # 5% tolerance

        if abs(actual_price - expected_price) <= price_tolerance:
            score += 10
            subscores["price_match"] = True
            feedback_parts.append(f"Sales price correct: {actual_price}")
        elif abs(actual_price - expected_price) <= expected_price * 0.2:
            score += 5  # Partial credit for close price
            feedback_parts.append(f"Sales price close: {actual_price} (expected: {expected_price})")
        elif actual_price > 0:
            score += 2
            feedback_parts.append(f"Sales price set: {actual_price} (expected: {expected_price})")
        else:
            feedback_parts.append(f"Sales price not set (expected: {expected_price})")
    except (ValueError, TypeError):
        feedback_parts.append("Invalid sales price value")

    # ================================================================
    # CRITERION 7: Cost within tolerance (5 points)
    # ================================================================
    try:
        actual_cost = float(product.get('cost', 0))
        cost_tolerance = expected_cost * 0.05  # 5% tolerance

        if abs(actual_cost - expected_cost) <= cost_tolerance:
            score += 5
            subscores["cost_match"] = True
            feedback_parts.append(f"Cost correct: {actual_cost}")
        elif actual_cost > 0:
            score += 2
            feedback_parts.append(f"Cost set: {actual_cost} (expected: {expected_cost})")
        else:
            feedback_parts.append(f"Cost not set (expected: {expected_cost})")
    except (ValueError, TypeError):
        feedback_parts.append("Invalid cost value")

    # ================================================================
    # CRITERION 8: Timestamp anti-gaming check (5 points)
    # ================================================================
    if task_start > 0 and task_end > 0:
        task_duration = task_end - task_start
        if task_duration > 10 and task_duration < 600:  # Between 10 sec and 10 min
            score += 5
            subscores["timestamp_check"] = True
            feedback_parts.append(f"Task completed in {task_duration}s (reasonable time)")
        elif task_duration >= 600:
            score += 3  # Partial credit - task took a long time but completed
            feedback_parts.append(f"Task took {task_duration}s (very long)")
        else:
            feedback_parts.append(f"Task completed too quickly ({task_duration}s) - suspicious")
    else:
        feedback_parts.append("Timestamp data unavailable")

    # ================================================================
    # FINAL DETERMINATION
    # ================================================================
    # Must have: product exists + newly created + correct type
    key_criteria_met = (
        subscores["product_exists"] and
        subscores["newly_created"] and
        subscores["correct_type"]
    )

    passed = score >= 65 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "expected_product": expected_name,
            "expected_type": expected_type,
            "expected_ref": expected_ref,
            "product_id": product.get('id', 'N/A'),
            "product_name": product.get('name', 'N/A'),
            "product_type": product.get('type', 'N/A'),
            "score_breakdown": {
                "product_exists": 25 if subscores["product_exists"] else 0,
                "newly_created": 20 if subscores["newly_created"] else 0,
                "correct_type": 15 if subscores["correct_type"] else 0,
                "ref_match": 10 if subscores["ref_match"] else 0,
                "barcode_match": 10 if subscores["barcode_match"] else 0,
                "price_match": 10 if subscores["price_match"] else 0,
                "cost_match": 5 if subscores["cost_match"] else 0,
                "timestamp_check": 5 if subscores["timestamp_check"] else 0
            }
        }
    }


# For local testing
if __name__ == "__main__":
    # Mock test
    test_result = {
        "task_start_time": 1700000000,
        "task_end_time": 1700000120,
        "initial_product_count": 10,
        "current_product_count": 11,
        "max_product_id_before": 10,
        "product_found": True,
        "newly_created": True,
        "product": {
            "id": "11",
            "name": "Industrial Safety Helmet",
            "internal_reference": "HELM-IND-001",
            "barcode": "5901234123457",
            "sales_price": "45.00",
            "cost": "28.00",
            "type": "product"
        },
        "validation": {
            "type_valid": True
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

    result = verify_create_product({}, env_info, task_info)
    print(f"Score: {result['score']}/100")
    print(f"Passed: {result['passed']}")
    print(f"Feedback: {result['feedback']}")
    print(f"Subscores: {result.get('subscores', {})}")
