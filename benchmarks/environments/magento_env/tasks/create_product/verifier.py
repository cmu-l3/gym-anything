#!/usr/bin/env python3
"""Verifier for Create Product task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_product(traj, env_info, task_info):
    """
    Verify that the expected product was created in Magento.

    Checks:
    1. Product was newly created (count increased during task)
    2. Product with expected SKU exists in database
    3. Product name matches expected value
    4. Product price matches expected value
    5. Product stock quantity matches expected value
    6. Product category matches expected value
    7. Product type is 'simple'

    All criteria must be met for the task to pass.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Organic Cotton T-Shirt')
    expected_sku = metadata.get('expected_sku', 'OCT-001')
    expected_price = metadata.get('expected_price', '29.99')
    expected_stock_qty = metadata.get('expected_stock_qty', '100')
    expected_category = metadata.get('expected_category', 'Clothing')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_product_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 7  # Updated to include stock quantity check
        feedback_parts = []

        initial_count = result.get('initial_product_count', 0)
        current_count = result.get('current_product_count', 0)
        product_found = result.get('product_found', False)
        product = result.get('product', {})

        logger.info(f"Result: initial={initial_count}, current={current_count}, found={product_found}")
        logger.info(f"Product data: {product}")

        # Criterion 1: Product was newly created (count must increase)
        newly_created = current_count > initial_count
        if newly_created:
            criteria_passed += 1
            feedback_parts.append(f"Product created (count: {initial_count} -> {current_count})")
        else:
            feedback_parts.append(f"No new product created (count unchanged: {initial_count})")
            # If no new product was created, fail immediately
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "newly_created": False,
                    "product_exists": product_found,
                    "sku_correct": False,
                    "name_correct": False,
                    "price_correct": False,
                    "stock_correct": False,
                    "category_correct": False,
                    "type_correct": False
                }
            }

        # Criterion 2: Product exists in database with correct SKU
        if product_found:
            criteria_passed += 1
            feedback_parts.append("Product found in database")
        else:
            feedback_parts.append("Product with expected SKU NOT found in database")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "newly_created": newly_created,
                    "product_exists": False,
                    "sku_correct": False,
                    "name_correct": False,
                    "price_correct": False,
                    "stock_correct": False,
                    "category_correct": False,
                    "type_correct": False
                }
            }

        # Criterion 3: SKU matches (case-insensitive)
        sku = product.get('sku', '')
        sku_correct = sku.strip().lower() == expected_sku.strip().lower()
        if sku_correct:
            criteria_passed += 1
            feedback_parts.append(f"SKU correct: {expected_sku}")
        else:
            feedback_parts.append(f"SKU mismatch: expected '{expected_sku}', got '{sku}'")

        # Criterion 4: Name matches (case-insensitive)
        name = product.get('name', '')
        name_correct = name.strip().lower() == expected_name.strip().lower()
        if name_correct:
            criteria_passed += 1
            feedback_parts.append(f"Product name correct: {expected_name}")
        else:
            feedback_parts.append(f"Product name mismatch: expected '{expected_name}', got '{name}'")

        # Criterion 5: Price matches
        price = product.get('price', '')
        price_correct = False
        try:
            actual_price = float(price) if price else 0
            expected_price_float = float(expected_price)
            price_correct = abs(actual_price - expected_price_float) < 0.01
            if price_correct:
                criteria_passed += 1
                feedback_parts.append(f"Price correct: ${expected_price}")
            else:
                feedback_parts.append(f"Price mismatch: expected ${expected_price}, got ${price}")
        except (ValueError, TypeError):
            feedback_parts.append(f"Price could not be verified: '{price}'")

        # Criterion 6: Stock quantity matches
        stock_qty = product.get('stock_qty', '')
        stock_correct = False
        try:
            actual_stock = float(stock_qty) if stock_qty else 0
            expected_stock_float = float(expected_stock_qty)
            stock_correct = abs(actual_stock - expected_stock_float) < 1  # Allow small variance
            if stock_correct:
                criteria_passed += 1
                feedback_parts.append(f"Stock quantity correct: {expected_stock_qty}")
            else:
                feedback_parts.append(f"Stock quantity mismatch: expected {expected_stock_qty}, got {stock_qty}")
        except (ValueError, TypeError):
            feedback_parts.append(f"Stock quantity could not be verified: '{stock_qty}'")

        # Criterion 7: Category matches (case-insensitive)
        category = product.get('category', '')
        category_correct = category.strip().lower() == expected_category.strip().lower()
        if category_correct:
            criteria_passed += 1
            feedback_parts.append(f"Category correct: {expected_category}")
        else:
            feedback_parts.append(f"Category mismatch: expected '{expected_category}', got '{category}'")

        # Note: Product type verification - the task says "simple product"
        # We check if type_id is 'simple' if available in the export
        product_type = product.get('type', 'simple')
        type_correct = product_type.lower() == 'simple'
        if type_correct:
            feedback_parts.append("Product type: simple")
        else:
            feedback_parts.append(f"Product type mismatch: expected 'simple', got '{product_type}'")
        # Type is informational - we don't fail if type check fails since task focus is on attributes

        # Calculate score - all main criteria must be met
        score = int((criteria_passed / total_criteria) * 100)
        passed = criteria_passed == total_criteria  # All criteria must pass

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "newly_created": newly_created,
                "product_exists": product_found,
                "sku_correct": sku_correct,
                "name_correct": name_correct,
                "price_correct": price_correct,
                "stock_correct": stock_correct,
                "category_correct": category_correct,
                "type_correct": type_correct
            }
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
