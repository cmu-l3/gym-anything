#!/usr/bin/env python3
"""
Verifier for Launch Coffee Product Line task in WooCommerce.

Stub verifier - real verification is done via external VLM evaluation.
Basic programmatic checks are included for structural validation.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_launch_coffee_product_line(traj, env_info, task_info):
    """Stub verifier - real verification is done via external VLM evaluation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    feedback_parts = []
    score = 0
    details = {}

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/launch_coffee_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {str(e)}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}

    # Stub: return basic score based on what was found
    categories = result.get('categories', {})
    product = result.get('product', {})
    variations = result.get('variations', [])
    shipping = result.get('shipping_class', {})
    coupon = result.get('coupon', {})
    order = result.get('order', {})

    if categories.get('artisan_coffee_exists') and categories.get('single_origin_exists'):
        score += 10
        feedback_parts.append("Categories created")
    if categories.get('single_origin_is_child_of_artisan'):
        score += 5
        feedback_parts.append("Category hierarchy correct")
    if product.get('found') and product.get('status') == 'publish':
        score += 10
        feedback_parts.append("Product found and published")
    if product.get('type', '').lower() in ('variable', 'variable product'):
        score += 5
        feedback_parts.append("Product is variable type")
    if len(variations) == 9:
        score += 10
        feedback_parts.append("9 variations found")
    if product.get('cross_sell_contains_oct'):
        score += 5
        feedback_parts.append("Cross-sell configured")
    if shipping.get('exists'):
        score += 5
        feedback_parts.append("Shipping class exists")
    if coupon.get('found'):
        score += 10
        feedback_parts.append("Coupon found")
    if order.get('found'):
        score += 10
        feedback_parts.append("Order found")
    if order.get('status') == 'wc-processing':
        score += 5
        feedback_parts.append("Order status correct")

    passed = score >= 50

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No checks passed",
        "details": details,
    }
