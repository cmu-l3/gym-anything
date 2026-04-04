#!/usr/bin/env python3
"""
Verifier for Add to Cart task in Drupal Commerce.

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_to_cart(traj, env_info, task_info):
    """
    Verify that the expected product was added to the shopping cart.

    Checks:
    1. A cart (draft order) exists
    2. The expected product is in the cart (order item with correct variation)
    3. Order count increased during session
    4. Cart has at least one item
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_product_title', 'Sony WH-1000XM5 Wireless Headphones')
    expected_sku = metadata.get('expected_product_sku', 'SONY-WH1000XM5')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        subscores = {}

        initial_orders = int(result.get('initial_order_count', 0))
        current_orders = int(result.get('current_order_count', 0))
        cart_count = int(result.get('cart_count', 0))

        product_in_cart = result.get('product_in_cart', False)
        if isinstance(product_in_cart, str):
            product_in_cart = product_in_cart.lower() == 'true'

        has_cart_with_items = result.get('has_cart_with_items', False)
        if isinstance(has_cart_with_items, str):
            has_cart_with_items = has_cart_with_items.lower() == 'true'

        total_items = int(result.get('total_order_items', 0))

        logger.info(f"Result: orders={initial_orders}->{current_orders}, carts={cart_count}, in_cart={product_in_cart}")

        # Criterion 1: A cart (draft order) exists
        if cart_count > 0:
            criteria_passed += 1
            subscores['cart_exists'] = 25
            feedback_parts.append(f"Cart exists ({cart_count} draft order(s))")
        else:
            subscores['cart_exists'] = 0
            feedback_parts.append("No cart (draft order) found")

        # Criterion 2: Expected product is in the cart
        if product_in_cart:
            order_item_qty = result.get('order_item_quantity', '0')
            criteria_passed += 1
            subscores['product_in_cart'] = 25
            feedback_parts.append(f"'{expected_title}' (SKU: {expected_sku}) is in the cart (qty: {order_item_qty})")
        else:
            subscores['product_in_cart'] = 0
            if total_items > 0:
                feedback_parts.append(f"Cart has {total_items} item(s) but '{expected_title}' not found")
            else:
                feedback_parts.append(f"'{expected_title}' NOT found in any cart")

        # Criterion 3: Order count increased
        if current_orders > initial_orders:
            criteria_passed += 1
            subscores['order_increased'] = 25
            feedback_parts.append(f"Order count increased: {initial_orders} -> {current_orders}")
        else:
            subscores['order_increased'] = 0
            feedback_parts.append(f"Order count unchanged: {initial_orders} -> {current_orders}")

        # Criterion 4: Cart has items
        if has_cart_with_items and total_items > 0:
            criteria_passed += 1
            subscores['cart_has_items'] = 25
            feedback_parts.append(f"Cart contains {total_items} item(s)")
        else:
            subscores['cart_has_items'] = 0
            feedback_parts.append("Cart is empty or no items found")

        score = int((criteria_passed / total_criteria) * 100)
        # Must have the specific product in cart to pass
        passed = product_in_cart and score >= 50

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
