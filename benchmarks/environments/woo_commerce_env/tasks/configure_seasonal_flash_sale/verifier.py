#!/usr/bin/env python3
"""
Verifier for Configure Seasonal Flash Sale task in WooCommerce.

This is a very_hard multi-feature task requiring the agent to:
1. Create a new product category 'Flash Sale'
2. Assign 3 existing products to that category
3. Set specific sale prices on each product
4. Create a coupon with complex restrictions (type, amount, min spend, usage limit,
   category restriction, expiry date)

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points):
  1. Flash Sale category exists (10 pts)
  2. Products assigned to Flash Sale category (15 pts - 5 each)
  3. Sale prices correct on target products (15 pts - 5 each)
  4. Coupon FLASH30 exists with correct type and amount (10 pts)
  5. Coupon minimum spend correct (5 pts)
  6. Coupon usage limit correct (5 pts)
  7. Coupon category restriction includes Flash Sale (5 pts)
  8. Coupon expiry date set (5 pts)

VLM checks (30 points):
  9. Process verification (15 pts)
  10. Final state verification (10 pts)
  11. Cross-validation (5 pts)

Pass threshold: 55 points AND category exists AND coupon found AND
at least 2 products correctly configured
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring a promotional flash sale in a WooCommerce store via the WordPress admin interface.

The images are sampled chronologically from the agent's full interaction (earliest to latest).

For successful flash sale configuration, the agent should progress through multiple areas:
1. Product category creation (Products > Categories, or while editing products)
2. Product editing (setting sale prices, assigning categories on multiple products)
3. Coupon creation (WooCommerce > Coupons > Add Coupon, filling in discount details, restrictions)
4. Saving/publishing changes

Assess:
1. WORKFLOW_COMPLETED: Did the agent work across multiple WooCommerce admin areas (products AND coupons)?
2. MULTI_AREA_NAVIGATION: Did the agent visit both product editing pages and coupon creation pages?
3. MEANINGFUL_PROGRESSION: Do the frames show real state changes across different admin sections?
4. SAVE_CONFIRMED: Is there evidence that changes were saved/published?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "multi_area_navigation": true/false,
    "meaningful_progression": true/false,
    "save_confirmed": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce flash sale configuration task.

This is a desktop screenshot showing the WordPress admin interface in a browser.

Assess:
1. ADMIN_VISIBLE: Is the WordPress/WooCommerce admin interface visible?
2. SUCCESS_INDICATORS: Are there success indicators (published message, saved confirmation, coupon or product page showing configured data)?
3. RELEVANT_PAGE: Is the current page related to products, coupons, or categories?
4. ERROR_INDICATORS: Are there error messages?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "relevant_page": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_configure_seasonal_flash_sale(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_products = metadata.get('target_products', [])
    expected_coupon_code = metadata.get('coupon_code', 'FLASH30')

    feedback_parts = []
    score = 0
    details = {}

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_seasonal_flash_sale_result.json", temp_result.name)
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

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # 1. Flash Sale category exists (10 pts)
    flash_cat_exists = result.get('flash_sale_category_exists', False)
    flash_cat_id = result.get('flash_sale_category_id', '')

    if flash_cat_exists:
        score += 10
        feedback_parts.append("Flash Sale category exists")
    else:
        feedback_parts.append("Flash Sale category NOT found")

    # 2. Products assigned to Flash Sale category (15 pts - 5 each)
    # 3. Sale prices correct (15 pts - 5 each)
    products = result.get('products', [])
    products_in_cat = 0
    products_with_correct_price = 0

    for product_data in products:
        sku = product_data.get('sku', '')
        name = product_data.get('name', sku)
        in_flash_cat = product_data.get('in_flash_sale_category', False)
        sale_price = product_data.get('sale_price', '')

        # Find expected sale price for this SKU
        expected_price = None
        for tp in target_products:
            if tp['sku'] == sku:
                expected_price = tp['expected_sale_price']
                break

        # Category check
        if in_flash_cat:
            score += 5
            products_in_cat += 1
            feedback_parts.append(f"{name}: in Flash Sale category")
        else:
            feedback_parts.append(f"{name}: NOT in Flash Sale category")

        # Sale price check
        if expected_price and sale_price:
            try:
                actual = float(sale_price)
                expected = float(expected_price)
                if abs(actual - expected) < 0.01:
                    score += 5
                    products_with_correct_price += 1
                    feedback_parts.append(f"{name}: sale price correct (${expected_price})")
                else:
                    feedback_parts.append(f"{name}: sale price wrong (expected ${expected_price}, got ${sale_price})")
            except (ValueError, TypeError):
                feedback_parts.append(f"{name}: sale price not parseable ('{sale_price}')")
        elif not sale_price:
            feedback_parts.append(f"{name}: no sale price set")

    # 4. Coupon FLASH30 exists with correct type and amount (10 pts)
    coupon_found = result.get('coupon_found', False)
    coupon = result.get('coupon', {})
    coupon_type_correct = False
    coupon_amount_correct = False

    if coupon_found:
        discount_type = coupon.get('discount_type', '')
        amount = coupon.get('amount', '')

        if discount_type == 'percent':
            coupon_type_correct = True

        try:
            if amount and abs(float(amount) - 30.0) < 0.01:
                coupon_amount_correct = True
        except (ValueError, TypeError):
            pass

        if coupon_type_correct and coupon_amount_correct:
            score += 10
            feedback_parts.append("Coupon FLASH30: correct type (percent) and amount (30)")
        elif coupon_type_correct or coupon_amount_correct:
            score += 5
            feedback_parts.append(f"Coupon FLASH30: partial match (type={discount_type}, amount={amount})")
        else:
            feedback_parts.append(f"Coupon FLASH30: wrong config (type={discount_type}, amount={amount})")
    else:
        feedback_parts.append("Coupon FLASH30 NOT found")

    # 5. Coupon minimum spend correct (5 pts)
    min_spend = coupon.get('minimum_amount', '')
    min_spend_correct = False
    try:
        if min_spend and abs(float(min_spend) - 50.0) < 0.01:
            score += 5
            min_spend_correct = True
            feedback_parts.append("Coupon min spend correct ($50)")
        elif min_spend:
            feedback_parts.append(f"Coupon min spend wrong: expected $50, got ${min_spend}")
        else:
            feedback_parts.append("Coupon min spend not set")
    except (ValueError, TypeError):
        feedback_parts.append(f"Coupon min spend not parseable: '{min_spend}'")

    # 6. Coupon usage limit correct (5 pts)
    usage_limit = coupon.get('usage_limit', '')
    usage_limit_correct = False
    try:
        if usage_limit and int(float(usage_limit)) == 100:
            score += 5
            usage_limit_correct = True
            feedback_parts.append("Coupon usage limit correct (100)")
        elif usage_limit:
            feedback_parts.append(f"Coupon usage limit wrong: expected 100, got {usage_limit}")
        else:
            feedback_parts.append("Coupon usage limit not set")
    except (ValueError, TypeError):
        feedback_parts.append(f"Coupon usage limit not parseable: '{usage_limit}'")

    # 7. Coupon category restriction includes Flash Sale (5 pts)
    cat_ids_raw = coupon.get('product_category_ids_raw', '')
    cat_restriction_correct = False
    if flash_cat_id and cat_ids_raw and str(flash_cat_id) in str(cat_ids_raw):
        score += 5
        cat_restriction_correct = True
        feedback_parts.append("Coupon restricted to Flash Sale category")
    elif cat_ids_raw:
        feedback_parts.append(f"Coupon has category restriction but Flash Sale ID ({flash_cat_id}) not found in it")
    else:
        feedback_parts.append("Coupon has no category restriction")

    # 8. Coupon expiry date set (5 pts)
    expiry = coupon.get('expiry', '')
    expiry_correct = False
    if expiry:
        try:
            # Handle Unix timestamp (WooCommerce stores date_expires as timestamp)
            expiry_ts = int(float(expiry))
            expiry_date = datetime.utcfromtimestamp(expiry_ts)
            if expiry_date.year == 2026 and expiry_date.month == 12 and expiry_date.day == 31:
                score += 5
                expiry_correct = True
                feedback_parts.append("Coupon expiry correct (2026-12-31)")
            else:
                feedback_parts.append(f"Coupon expiry wrong date: {expiry_date.strftime('%Y-%m-%d')}")
        except (ValueError, TypeError, OSError):
            # Try as date string
            if '2026-12-31' in str(expiry):
                score += 5
                expiry_correct = True
                feedback_parts.append("Coupon expiry correct (2026-12-31)")
            elif expiry:
                feedback_parts.append(f"Coupon expiry set but value unclear: {expiry}")
    else:
        feedback_parts.append("Coupon expiry not set")

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')
    vlm_workflow_confirmed = False
    vlm_available = False

    sampled_frames = sample_frames(traj, num_samples=6) if sample_frames else []
    final_frame = get_final(traj) if get_final else None

    has_trajectory = len(sampled_frames) >= 2
    has_final = final_frame is not None

    details['vlm_trajectory_frames'] = len(sampled_frames)
    details['vlm_has_final_frame'] = has_final

    if query_vlm and (has_trajectory or has_final):
        vlm_available = True

        if has_trajectory:
            process_result = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames)
            details['vlm_process'] = process_result
            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                multi_area = process_result.get('multi_area_navigation', False)
                progression_ok = process_result.get('meaningful_progression', False)
                if workflow_ok and multi_area:
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Multi-area workflow confirmed")
                elif workflow_ok or multi_area:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Workflow partially confirmed")
                elif progression_ok:
                    score += 5
                    feedback_parts.append("VLM process: Some progression seen")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")

        if has_final:
            final_result = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
            details['vlm_final_state'] = final_result
            if final_result:
                admin_ok = final_result.get('admin_visible', False)
                success_ok = final_result.get('success_indicators', False)
                error_found = final_result.get('error_indicators', False)
                if admin_ok and success_ok and not error_found:
                    score += 10
                    feedback_parts.append("VLM final: Success indicators visible")
                elif admin_ok and success_ok:
                    score += 7
                    feedback_parts.append("VLM final: Success with warnings")
                elif admin_ok:
                    score += 4
                    feedback_parts.append("VLM final: Admin visible")

        if flash_cat_exists and coupon_found and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: Category + coupon + VLM agree")
            details['cross_validation'] = 'pass'
        elif (flash_cat_exists or coupon_found) and vlm_workflow_confirmed:
            score += 2
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'
    else:
        feedback_parts.append("VLM checks skipped (unavailable)")

    # ================================================================
    # PASS CRITERIA
    # ================================================================
    # Category must exist, coupon must be found, at least 2 products configured
    min_products_ok = (products_in_cat >= 2 and products_with_correct_price >= 2)

    if vlm_available:
        passed = score >= 55 and flash_cat_exists and coupon_found and min_products_ok and vlm_workflow_confirmed
    else:
        passed = score >= 55 and flash_cat_exists and coupon_found and min_products_ok

    details.update({
        "flash_cat_exists": flash_cat_exists,
        "products_in_cat": products_in_cat,
        "products_with_correct_price": products_with_correct_price,
        "coupon_found": coupon_found,
        "coupon_type_correct": coupon_type_correct,
        "coupon_amount_correct": coupon_amount_correct,
        "min_spend_correct": min_spend_correct,
        "usage_limit_correct": usage_limit_correct,
        "cat_restriction_correct": cat_restriction_correct,
        "expiry_correct": expiry_correct,
        "vlm_available": vlm_available,
        "vlm_workflow_confirmed": vlm_workflow_confirmed,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
