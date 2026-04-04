#!/usr/bin/env python3
"""
Verifier for setup_woocommerce_store task.

Occupation: E-Commerce Manager / Marketing Manager (SOC 11-2021.00)
Difficulty: Very Hard

Agent must activate WooCommerce, create a product category, add 3 products
with specific names/prices/SKUs, and configure store currency.

Programmatic checks (70 points):
  1. WooCommerce plugin is active (10 pts)
  2. Product category 'Artisan Coffee Blends' exists (10 pts)
  3. Product 'Ethiopian Yirgacheffe' correct price+SKU+category (15 pts)
  4. Product 'Colombian Supremo' correct price+SKU+category (15 pts)
  5. Product 'Sumatra Mandheling' correct price+SKU+category (15 pts)
  6. Store currency is USD (5 pts)

VLM checks (30 points):
  7. Trajectory shows WooCommerce configuration (15 pts)
  8. Final state shows products or store admin (10 pts)
  9. Cross-validation (5 pts)

Pass threshold: score >= 70 AND WooCommerce active AND all 3 products found
"""

import json
import tempfile
import os
import logging

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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots from an agent setting up a WooCommerce online store in WordPress.

The agent should progress through:
1. Navigating to Plugins and activating WooCommerce
2. Dismissing or completing the WooCommerce setup wizard
3. Creating a product category
4. Adding products with prices and details
5. Configuring store settings (currency)

Assess:
1. WORKFLOW_COMPLETED: Did the agent activate WooCommerce and add products?
2. PRODUCT_CREATION: Are product creation/editing forms visible?
3. STORE_CONFIG: Are WooCommerce settings pages visible?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "product_creation": true/false,
    "store_config": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce store setup task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress/WooCommerce admin visible?
2. SUCCESS_INDICATORS: Are products visible in a product list or store dashboard?
3. STORE_CONFIGURED: Does the WooCommerce admin show configured settings?
4. ERROR_INDICATORS: Any errors visible?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "store_configured": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def _check_product(product_data, expected_price, expected_sku):
    """Check a single product's attributes. Returns (points, feedback)."""
    if not product_data.get('found', False):
        return 0, "not found"

    points = 5  # base points for existing
    parts = []

    if product_data.get('price_correct', False):
        points += 4
        parts.append("price OK")
    else:
        actual = product_data.get('actual_price', '')
        parts.append(f"price WRONG (got '{actual}', expected '{expected_price}')")

    if product_data.get('sku_correct', False):
        points += 3
        parts.append("SKU OK")
    else:
        actual = product_data.get('actual_sku', '')
        parts.append(f"SKU WRONG (got '{actual}', expected '{expected_sku}')")

    if product_data.get('in_category', False):
        points += 3
        parts.append("category OK")
    else:
        parts.append("NOT in 'Artisan Coffee Blends'")

    return points, ", ".join(parts)


def verify_setup_woocommerce_store(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    details = {}

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/setup_woocommerce_store_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False, "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    products = result.get('products', {})

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # Criterion 1: WooCommerce active (10 pts)
    wc_active = result.get('woocommerce_active', False)
    if wc_active:
        score += 10
        feedback_parts.append("WooCommerce active")
    else:
        feedback_parts.append("FAIL: WooCommerce not active")

    # Criterion 2: Product category exists (10 pts)
    cat_exists = result.get('category_exists', False)
    if cat_exists:
        score += 10
        feedback_parts.append("Category 'Artisan Coffee Blends' exists")
    else:
        feedback_parts.append("FAIL: Category 'Artisan Coffee Blends' not found")

    # Criterion 3: Ethiopian Yirgacheffe (15 pts)
    p1 = products.get('ethiopian_yirgacheffe', {})
    p1_pts, p1_fb = _check_product(p1, "18.99", "ACB-ETH-001")
    score += p1_pts
    feedback_parts.append(f"Ethiopian Yirgacheffe: {p1_fb}")

    # Criterion 4: Colombian Supremo (15 pts)
    p2 = products.get('colombian_supremo', {})
    p2_pts, p2_fb = _check_product(p2, "15.49", "ACB-COL-002")
    score += p2_pts
    feedback_parts.append(f"Colombian Supremo: {p2_fb}")

    # Criterion 5: Sumatra Mandheling (15 pts)
    p3 = products.get('sumatra_mandheling', {})
    p3_pts, p3_fb = _check_product(p3, "16.99", "ACB-SUM-003")
    score += p3_pts
    feedback_parts.append(f"Sumatra Mandheling: {p3_fb}")

    # Criterion 6: Store currency USD (5 pts)
    currency = result.get('store_currency', '')
    if currency.upper() == 'USD':
        score += 5
        feedback_parts.append("Store currency: USD")
    elif currency:
        feedback_parts.append(f"FAIL: Store currency is '{currency}' (expected USD)")
    else:
        feedback_parts.append("FAIL: Store currency not set")

    all_products_found = (
        p1.get('found', False) and
        p2.get('found', False) and
        p3.get('found', False)
    )

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')
    vlm_workflow_confirmed = False
    vlm_available = False
    vlm_query_failed = False

    sampled_frames = sample_frames(traj, num_samples=12) if sample_frames else []
    final_frame = get_final(traj) if get_final else None

    has_trajectory = len(sampled_frames) >= 2
    has_final = final_frame is not None

    details['vlm_trajectory_frames'] = len(sampled_frames)
    details['vlm_has_final_frame'] = has_final

    if query_vlm and (has_trajectory or has_final):
        vlm_available = True

        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )
            details['vlm_process'] = process_result

            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                progression_ok = process_result.get('meaningful_progression', False)
                product_ok = process_result.get('product_creation', False)

                if workflow_ok and progression_ok:
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Full store setup confirmed")
                elif workflow_ok or product_ok:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Partially confirmed")
                elif progression_ok:
                    score += 5
                    feedback_parts.append("VLM process: Some progression")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")
            else:
                vlm_query_failed = True
                feedback_parts.append("VLM process check failed")
        else:
            feedback_parts.append("VLM process: Insufficient frames")

        if has_final:
            final_result = _vlm_query(
                query_vlm, FINAL_STATE_PROMPT, image=final_frame
            )
            details['vlm_final_state'] = final_result

            if final_result:
                admin_ok = final_result.get('admin_visible', False)
                success_ok = final_result.get('success_indicators', False)
                error_found = final_result.get('error_indicators', False)

                if admin_ok and success_ok and not error_found:
                    score += 10
                    feedback_parts.append("VLM final: Store setup confirmed")
                elif admin_ok and success_ok:
                    score += 7
                    feedback_parts.append("VLM final: Success with warnings")
                elif admin_ok:
                    score += 4
                    feedback_parts.append("VLM final: Admin visible")
                else:
                    feedback_parts.append("VLM final: Admin not visible")
            else:
                feedback_parts.append("VLM final check failed")
        else:
            feedback_parts.append("VLM final: No frame")

        if all_products_found and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: products + VLM agree")
            details['cross_validation'] = 'pass'
        elif all_products_found and not vlm_workflow_confirmed:
            feedback_parts.append("Cross-validation mismatch")
            details['cross_validation'] = 'mismatch'
        elif vlm_workflow_confirmed and not all_products_found:
            score += 2
            feedback_parts.append("Cross-validation: VLM sees setup but products missing")
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'
    else:
        feedback_parts.append("VLM checks skipped")

    # ================================================================
    # PASS CRITERIA
    # ================================================================
    vlm_required_for_pass = vlm_available and not vlm_query_failed

    if vlm_required_for_pass:
        passed = (score >= 70 and wc_active and all_products_found and
                  vlm_workflow_confirmed)
    else:
        passed = score >= 70 and wc_active and all_products_found

    details.update({
        "wc_active": wc_active,
        "category_exists": cat_exists,
        "all_products_found": all_products_found,
        "product_1_found": p1.get('found', False),
        "product_2_found": p2.get('found', False),
        "product_3_found": p3.get('found', False),
        "currency_correct": currency.upper() == 'USD' if currency else False,
        "vlm_available": vlm_available,
        "vlm_query_failed": vlm_query_failed,
        "vlm_workflow_confirmed": vlm_workflow_confirmed,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
