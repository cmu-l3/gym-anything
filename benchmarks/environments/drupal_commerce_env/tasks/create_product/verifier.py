#!/usr/bin/env python3
"""
Verifier for Create Product task in Drupal Commerce.

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_product(traj, env_info, task_info):
    """
    Verify that the expected product was created in Drupal Commerce.

    Checks:
    1. Product with expected title exists in database
    2. Product SKU matches expected value
    3. Product price matches expected value
    4. Product is published (not draft)
    5. Product was created during this session (count increased)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', 'Organic Bamboo Wireless Charger')
    expected_sku = metadata.get('expected_sku', 'OBW-CHR-01')
    expected_price = metadata.get('expected_price', '39.99')
    expected_status = metadata.get('expected_status', 'published')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        subscores = {}

        initial_count = int(result.get('initial_product_count', 0))
        current_count = int(result.get('current_product_count', 0))
        product_found = result.get('product_found', False)
        if isinstance(product_found, str):
            product_found = product_found.lower() == 'true'

        logger.info(f"Result: initial={initial_count}, current={current_count}, found={product_found}")

        # Criterion 1: Product with expected title exists
        if product_found:
            title = result.get('product_title', '')
            if title.strip().lower() == expected_title.lower():
                criteria_passed += 1
                subscores['title_match'] = 20
                feedback_parts.append(f"Product '{expected_title}' found")
            else:
                subscores['title_match'] = 10  # partial - found but name differs
                feedback_parts.append(f"Product name mismatch: expected '{expected_title}', got '{title}'")
        else:
            subscores['title_match'] = 0
            feedback_parts.append(f"Product '{expected_title}' NOT found in database")
            if current_count > initial_count:
                feedback_parts.append(f"Note: {current_count - initial_count} new product(s) added, but not with expected title")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # Criterion 2: SKU matches
        product_sku = result.get('product_sku', '')
        sku_found = result.get('sku_found', False)
        if isinstance(sku_found, str):
            sku_found = sku_found.lower() == 'true'

        if product_sku.strip().upper() == expected_sku.upper():
            criteria_passed += 1
            subscores['sku_match'] = 20
            feedback_parts.append(f"SKU correct: {expected_sku}")
        elif sku_found:
            criteria_passed += 0.5
            subscores['sku_match'] = 10
            feedback_parts.append(f"SKU '{expected_sku}' exists but not linked to this product (got '{product_sku}')")
        else:
            subscores['sku_match'] = 0
            feedback_parts.append(f"SKU mismatch: expected '{expected_sku}', got '{product_sku}'")

        # Criterion 3: Price matches
        product_price = result.get('product_price', '')
        try:
            actual_price = float(product_price) if product_price else 0.0
            exp_price = float(expected_price)
            if abs(actual_price - exp_price) < 0.01:
                criteria_passed += 1
                subscores['price_match'] = 20
                feedback_parts.append(f"Price correct: ${expected_price}")
            else:
                subscores['price_match'] = 0
                feedback_parts.append(f"Price mismatch: expected ${expected_price}, got ${actual_price:.2f}")
        except (ValueError, TypeError):
            subscores['price_match'] = 0
            feedback_parts.append(f"Price could not be verified: '{product_price}'")

        # Criterion 4: Product is published
        product_status = result.get('product_status', '')
        if product_status == expected_status:
            criteria_passed += 1
            subscores['status_match'] = 20
            feedback_parts.append("Product is published")
        else:
            subscores['status_match'] = 0
            feedback_parts.append(f"Product status: expected '{expected_status}', got '{product_status}'")

        # Criterion 5: Product count increased
        if current_count > initial_count:
            criteria_passed += 1
            subscores['count_increased'] = 20
            feedback_parts.append(f"Product count increased: {initial_count} -> {current_count}")
        else:
            subscores['count_increased'] = 0
            feedback_parts.append(f"Product count did not increase: {initial_count} -> {current_count}")

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 60 and product_found

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

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
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
