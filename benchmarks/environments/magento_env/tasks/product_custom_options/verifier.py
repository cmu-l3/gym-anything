#!/usr/bin/env python3
"""Verifier for Product Custom Options task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_product_custom_options(traj, env_info, task_info):
    """
    Verify that the product custom option was created correctly.

    Criteria:
    1. Option exists on BOTTLE-001 (20 pts)
    2. Title matches "Laser Engraving" (20 pts)
    3. Type matches "field" (Text Field) (15 pts)
    4. Price matches 4.99 (15 pts)
    5. SKU matches "engrave" (10 pts)
    6. Max Characters matches 15 (10 pts)
    7. Required is No (0) (10 pts)

    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_option_title', 'Laser Engraving')
    expected_type = metadata.get('expected_option_type', 'field')
    expected_price = metadata.get('expected_price', '4.99')
    expected_sku = metadata.get('expected_sku', 'engrave')
    expected_max_chars = metadata.get('expected_max_chars', '15')
    expected_is_require = metadata.get('expected_is_require', False)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/custom_options_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        option_found = result.get('option_found', False)
        option = result.get('option', {})
        initial_count = result.get('initial_option_count', 0)
        current_count = result.get('current_option_count', 0)

        logger.info(f"Result: found={option_found}, option={option}")

        # Criterion 1: Option exists (20 pts)
        if option_found and current_count > initial_count:
            score += 20
            feedback_parts.append("Custom option created on BOTTLE-001")
        elif option_found:
            # Found but count didn't increase? Might have edited existing (unlikely given setup) or setup failed
            score += 10
            feedback_parts.append("Custom option found (but count didn't increase)")
        else:
            feedback_parts.append("No custom option found on product")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "details": {"error": "Option not created"}
            }

        # Criterion 2: Title matches (20 pts)
        title = option.get('title', '').strip()
        if title.lower() == expected_title.lower():
            score += 20
            feedback_parts.append(f"Title correct: {title}")
        else:
            feedback_parts.append(f"Title mismatch: expected '{expected_title}', got '{title}'")

        # Criterion 3: Type matches (15 pts)
        # 'field' is the database value for Text > Field
        opt_type = option.get('type', '').strip()
        if opt_type == expected_type:
            score += 15
            feedback_parts.append("Option type correct (Text Field)")
        else:
            feedback_parts.append(f"Type mismatch: expected '{expected_type}', got '{opt_type}'")

        # Criterion 4: Price matches (15 pts)
        # Allow slight formatting diffs (4.99 vs 4.9900)
        try:
            price_val = float(option.get('price', 0))
            expected_price_val = float(expected_price)
            if abs(price_val - expected_price_val) < 0.01:
                score += 15
                feedback_parts.append(f"Price correct: {expected_price}")
            else:
                feedback_parts.append(f"Price mismatch: expected {expected_price}, got {price_val}")
        except ValueError:
             feedback_parts.append(f"Invalid price format found")

        # Criterion 5: SKU matches (10 pts)
        sku = option.get('sku', '').strip()
        if sku.lower() == expected_sku.lower():
            score += 10
            feedback_parts.append(f"SKU correct: {sku}")
        else:
            feedback_parts.append(f"SKU mismatch: expected '{expected_sku}', got '{sku}'")

        # Criterion 6: Max Characters matches (10 pts)
        max_chars = str(option.get('max_characters', '')).strip()
        if max_chars == expected_max_chars:
            score += 10
            feedback_parts.append(f"Max characters correct: {max_chars}")
        else:
            feedback_parts.append(f"Max characters mismatch: expected {expected_max_chars}, got '{max_chars}'")

        # Criterion 7: Required matches (10 pts)
        # Database stores 1 for true, 0 for false
        is_require = str(option.get('is_require', '')).strip()
        expected_req_val = '1' if expected_is_require else '0'
        
        if is_require == expected_req_val:
            score += 10
            feedback_parts.append(f"Required setting correct: {'Yes' if expected_is_require else 'No'}")
        else:
            feedback_parts.append(f"Required setting mismatch: expected {'Yes' if expected_is_require else 'No'}")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}