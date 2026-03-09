#!/usr/bin/env python3
"""
Verifier for Create Coupon task in Drupal Commerce.

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_coupon(traj, env_info, task_info):
    """
    Verify that the expected promotion with coupon was created in Drupal Commerce.

    Checks:
    1. Promotion with expected name exists in database
    2. Promotion is active/enabled
    3. Coupon code exists and matches expected value
    4. Offer type is percentage-based
    5. Promotion/coupon count increased during session
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_promotion_name', 'Summer Sale 20% Off')
    expected_coupon = metadata.get('expected_coupon_code', 'SUMMER20')
    expected_discount_type = metadata.get('expected_discount_type', 'percentage')

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

        initial_promo = int(result.get('initial_promotion_count', 0))
        current_promo = int(result.get('current_promotion_count', 0))
        initial_coupon = int(result.get('initial_coupon_count', 0))
        current_coupon = int(result.get('current_coupon_count', 0))

        promo_found = result.get('promotion_found', False)
        if isinstance(promo_found, str):
            promo_found = promo_found.lower() == 'true'

        coupon_found = result.get('coupon_found', False)
        if isinstance(coupon_found, str):
            coupon_found = coupon_found.lower() == 'true'

        logger.info(f"Result: promos={initial_promo}->{current_promo}, coupons={initial_coupon}->{current_coupon}")

        # Criterion 1: Promotion with expected name exists
        if promo_found:
            promo_name = result.get('promotion_name', '')
            if promo_name.strip().lower() == expected_name.lower():
                criteria_passed += 1
                subscores['name_match'] = 20
                feedback_parts.append(f"Promotion '{expected_name}' found")
            else:
                criteria_passed += 0.5
                subscores['name_match'] = 10
                feedback_parts.append(f"Promotion found but name differs: expected '{expected_name}', got '{promo_name}'")
        else:
            subscores['name_match'] = 0
            feedback_parts.append(f"Promotion '{expected_name}' NOT found in database")
            if current_promo > initial_promo:
                feedback_parts.append(f"Note: {current_promo - initial_promo} new promotion(s) added, but not with expected name")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # Criterion 2: Promotion is active
        promo_status = result.get('promotion_status', '')
        if promo_status == 'active':
            criteria_passed += 1
            subscores['promo_active'] = 20
            feedback_parts.append("Promotion is active")
        else:
            subscores['promo_active'] = 0
            feedback_parts.append(f"Promotion status: '{promo_status}' (expected 'active')")

        # Criterion 3: Coupon code matches
        if coupon_found:
            coupon_code = result.get('coupon_code', '')
            if coupon_code.strip().upper() == expected_coupon.upper():
                criteria_passed += 1
                subscores['coupon_match'] = 20
                feedback_parts.append(f"Coupon code '{expected_coupon}' found")
            else:
                subscores['coupon_match'] = 10
                feedback_parts.append(f"Coupon found but code differs: expected '{expected_coupon}', got '{coupon_code}'")
        else:
            subscores['coupon_match'] = 0
            feedback_parts.append(f"Coupon code '{expected_coupon}' NOT found")

        # Criterion 4: Offer type is percentage
        is_percentage = result.get('is_percentage', False)
        if isinstance(is_percentage, str):
            is_percentage = is_percentage.lower() == 'true'

        offer_type = result.get('offer_type', '')
        if is_percentage or 'percentage' in offer_type.lower():
            criteria_passed += 1
            subscores['offer_type'] = 20
            feedback_parts.append("Offer type is percentage-based")
        elif offer_type:
            subscores['offer_type'] = 0
            feedback_parts.append(f"Offer type mismatch: expected percentage, got '{offer_type}'")
        else:
            subscores['offer_type'] = 5
            feedback_parts.append("Could not verify offer type")

        # Criterion 5: Counts increased
        promo_increased = current_promo > initial_promo
        coupon_increased = current_coupon > initial_coupon
        if promo_increased and coupon_increased:
            criteria_passed += 1
            subscores['counts_increased'] = 20
            feedback_parts.append(f"Promotion count: {initial_promo}->{current_promo}, Coupon count: {initial_coupon}->{current_coupon}")
        elif promo_increased:
            criteria_passed += 0.5
            subscores['counts_increased'] = 10
            feedback_parts.append(f"Promotion count increased ({initial_promo}->{current_promo}) but coupon count unchanged")
        else:
            subscores['counts_increased'] = 0
            feedback_parts.append(f"Counts did not increase: promos {initial_promo}->{current_promo}, coupons {initial_coupon}->{current_coupon}")

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 60 and promo_found and coupon_found

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
