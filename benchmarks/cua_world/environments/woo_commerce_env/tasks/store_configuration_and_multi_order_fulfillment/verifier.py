#!/usr/bin/env python3
"""
Verifier for Store Configuration and Multi-Order Fulfillment task in WooCommerce.

This is a very_hard task requiring the agent to:
1. Enable and configure COD payment method
2. Create a shipping class and assign it to products
3. Create two orders with different customers, products, statuses, and notes

Verification Strategy (Hybrid: Programmatic + VLM):

Programmatic checks (70 points):
  1. COD payment enabled with correct title/description (10 pts)
  2. Shipping class 'Oversized Items' exists (5 pts)
  3. Shipping class assigned to correct products (10 pts: 5 each)
  4. Order A exists with correct products (8 pts)
  5. Order A assigned to Mike Wilson (3 pts)
  6. Order A status is 'completed' (4 pts)
  7. Order A has correct note (5 pts)
  8. Order B exists with correct products (8 pts)
  9. Order B assigned to John Doe (3 pts)
  10. Order B status is 'processing' (4 pts)
  11. Order B has correct note (5 pts)
  12. At least 2 new orders created (5 pts)

VLM checks (30 points):
  13. Process verification (15 pts)
  14. Final state verification (10 pts)
  15. Cross-validation (5 pts)

Pass threshold: 45 points AND at least one order found AND shipping class exists
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring a WooCommerce store (payment methods, shipping classes) and creating multiple orders.

The images are sampled chronologically (earliest to latest).

For success, the agent should work across multiple WooCommerce admin areas:
1. WooCommerce > Settings > Payments (enable/configure payment method)
2. WooCommerce > Settings > Shipping > Shipping classes (create shipping class)
3. Product editing (assign shipping class to products)
4. WooCommerce > Orders (create multiple orders with different details)

Assess:
1. WORKFLOW_COMPLETED: Did the agent work across settings, products, and orders?
2. SETTINGS_CONFIGURATION: Did the agent visit WooCommerce payment or shipping settings?
3. MULTIPLE_ORDERS: Did the agent create more than one order?
4. MULTI_AREA_PROGRESSION: Do frames show different admin sections?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "settings_configuration": true/false,
    "multiple_orders": true/false,
    "multi_area_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce store configuration and order creation task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress/WooCommerce admin interface visible?
2. SUCCESS_INDICATORS: Are there success indicators (order created, settings saved)?
3. ORDER_OR_SETTINGS: Is an order page or settings page visible?
4. ERROR_INDICATORS: Are there error messages?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "order_or_settings": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def _check_order_products(order_items, expected_products):
    """Check if order line items match expected products. Returns count of correct matches."""
    correct = 0
    for expected in expected_products:
        exp_name = expected['name'].lower()
        exp_sku = expected.get('sku', '').lower()
        exp_qty = int(expected['quantity'])

        for item in order_items:
            item_name = item.get('name', '').lower()
            item_sku = item.get('sku', '').lower()
            item_qty = int(float(item.get('quantity', 0)))

            if (exp_name in item_name or item_name in exp_name or
                    (exp_sku and exp_sku == item_sku)):
                if item_qty == exp_qty:
                    correct += 1
                break

    return correct


def verify_store_configuration_and_multi_order_fulfillment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    order_a_meta = metadata.get('order_a', {})
    order_b_meta = metadata.get('order_b', {})

    feedback_parts = []
    score = 0
    details = {}

    # Load result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/store_config_multi_order_result.json", temp_result.name)
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

    # 1. COD payment enabled with correct title/description (10 pts)
    cod = result.get('cod', {})
    cod_enabled = cod.get('enabled', False)
    cod_title = cod.get('title', '')
    cod_desc = cod.get('description', '')
    cod_ok = False

    if cod_enabled:
        title_ok = 'pay on delivery' in cod_title.lower() if cod_title else False
        desc_ok = 'pay with cash' in cod_desc.lower() if cod_desc else False

        if title_ok and desc_ok:
            score += 10
            cod_ok = True
            feedback_parts.append("COD enabled with correct title and description")
        elif title_ok or desc_ok:
            score += 7
            cod_ok = True
            feedback_parts.append("COD enabled with partially correct settings")
        else:
            score += 4
            cod_ok = True
            feedback_parts.append(f"COD enabled but title/desc differ (title='{cod_title}')")
    else:
        feedback_parts.append("COD payment NOT enabled")

    # 2. Shipping class exists (5 pts)
    sc = result.get('shipping_class', {})
    sc_exists = sc.get('exists', False)
    if sc_exists:
        score += 5
        feedback_parts.append("Shipping class 'Oversized Items' exists")
    else:
        feedback_parts.append("Shipping class 'Oversized Items' NOT found")

    # 3. Shipping class assigned to products (10 pts: 5 each)
    sc_assignments = 0
    if sc.get('pch_assigned', False):
        score += 5
        sc_assignments += 1
        feedback_parts.append("Shipping class: Camping Hammock assigned")
    else:
        feedback_parts.append("Shipping class: Camping Hammock NOT assigned")

    if sc.get('cpp_assigned', False):
        score += 5
        sc_assignments += 1
        feedback_parts.append("Shipping class: Plant Pot Set assigned")
    else:
        feedback_parts.append("Shipping class: Plant Pot Set NOT assigned")

    # 4-7. Order A (20 pts total)
    order_a = result.get('order_a', {})
    order_a_found = order_a.get('found', False)
    order_a_valid = False

    if order_a_found:
        # Products (8 pts)
        a_items = order_a.get('line_items', [])
        a_expected = order_a_meta.get('products', [])
        a_products_correct = _check_order_products(a_items, a_expected)

        if a_products_correct == len(a_expected):
            score += 8
            feedback_parts.append(f"Order A products: all {a_products_correct} correct")
        elif a_products_correct > 0:
            score += int(8 * a_products_correct / len(a_expected))
            feedback_parts.append(f"Order A products: {a_products_correct}/{len(a_expected)} correct")
        else:
            feedback_parts.append("Order A products: none correct")

        # Customer (3 pts)
        a_email = order_a.get('customer_email', '').lower().strip()
        if a_email == order_a_meta.get('customer_email', '').lower():
            score += 3
            feedback_parts.append("Order A customer: Mike Wilson")
        else:
            feedback_parts.append(f"Order A customer wrong: {a_email}")

        # Status (4 pts)
        a_status = order_a.get('status', '').lower().strip()
        a_status_ok = a_status in ('wc-completed', 'completed')
        if a_status_ok:
            score += 4
            order_a_valid = True
            feedback_parts.append("Order A status: completed")
        else:
            feedback_parts.append(f"Order A status wrong: '{a_status}'")

        # Note (5 pts)
        a_note = order_a.get('note', '').lower()
        if 'express courier' in a_note:
            score += 5
            feedback_parts.append("Order A note: correct")
        elif a_note:
            score += 2
            feedback_parts.append("Order A note exists but content differs")
        else:
            feedback_parts.append("Order A: no note found")
    else:
        feedback_parts.append("Order A NOT found")

    # 8-11. Order B (20 pts total)
    order_b = result.get('order_b', {})
    order_b_found = order_b.get('found', False)
    order_b_valid = False

    if order_b_found:
        # Products (8 pts)
        b_items = order_b.get('line_items', [])
        b_expected = order_b_meta.get('products', [])
        b_products_correct = _check_order_products(b_items, b_expected)

        if b_products_correct == len(b_expected):
            score += 8
            feedback_parts.append(f"Order B products: all {b_products_correct} correct")
        elif b_products_correct > 0:
            score += int(8 * b_products_correct / len(b_expected))
            feedback_parts.append(f"Order B products: {b_products_correct}/{len(b_expected)} correct")
        else:
            feedback_parts.append("Order B products: none correct")

        # Customer (3 pts)
        b_email = order_b.get('customer_email', '').lower().strip()
        if b_email == order_b_meta.get('customer_email', '').lower():
            score += 3
            feedback_parts.append("Order B customer: John Doe")
        else:
            feedback_parts.append(f"Order B customer wrong: {b_email}")

        # Status (4 pts)
        b_status = order_b.get('status', '').lower().strip()
        b_status_ok = b_status in ('wc-processing', 'processing')
        if b_status_ok:
            score += 4
            order_b_valid = True
            feedback_parts.append("Order B status: processing")
        else:
            feedback_parts.append(f"Order B status wrong: '{b_status}'")

        # Note (5 pts)
        b_note = order_b.get('note', '').lower()
        if 'gift wrapping' in b_note:
            score += 5
            feedback_parts.append("Order B note: correct")
        elif b_note:
            score += 2
            feedback_parts.append("Order B note exists but content differs")
        else:
            feedback_parts.append("Order B: no note found")
    else:
        feedback_parts.append("Order B NOT found")

    # 12. At least 2 new orders (5 pts)
    initial_count = result.get('initial_order_count', 0)
    current_count = result.get('current_order_count', 0)
    new_orders = current_count - initial_count

    if new_orders >= 2:
        score += 5
        feedback_parts.append(f"New orders: {new_orders}")
    elif new_orders == 1:
        score += 2
        feedback_parts.append("Only 1 new order (expected 2)")
    else:
        feedback_parts.append("No new orders created")

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
                settings_ok = process_result.get('settings_configuration', False)
                multi_orders = process_result.get('multiple_orders', False)
                multi_area = process_result.get('multi_area_progression', False)
                if workflow_ok and (multi_orders or multi_area):
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Multi-area workflow with orders confirmed")
                elif workflow_ok or settings_ok:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Workflow confirmed")
                elif multi_orders or multi_area:
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
                if admin_ok and success_ok:
                    score += 10
                    feedback_parts.append("VLM final: Success indicators visible")
                elif admin_ok:
                    score += 4
                    feedback_parts.append("VLM final: Admin visible")

        if (order_a_found or order_b_found) and sc_exists and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: Orders + shipping class + VLM agree")
            details['cross_validation'] = 'pass'
        else:
            details['cross_validation'] = 'partial' if vlm_workflow_confirmed else 'neither'
    else:
        feedback_parts.append("VLM checks skipped (unavailable)")

    # ================================================================
    # PASS CRITERIA
    # ================================================================
    any_order_found = order_a_found or order_b_found

    if vlm_available:
        passed = score >= 45 and any_order_found and sc_exists and vlm_workflow_confirmed
    else:
        passed = score >= 45 and any_order_found and sc_exists

    details.update({
        "cod_enabled": cod_enabled,
        "cod_ok": cod_ok,
        "sc_exists": sc_exists,
        "sc_assignments": sc_assignments,
        "order_a_found": order_a_found,
        "order_a_valid": order_a_valid,
        "order_b_found": order_b_found,
        "order_b_valid": order_b_valid,
        "new_orders": new_orders,
        "vlm_available": vlm_available,
        "vlm_workflow_confirmed": vlm_workflow_confirmed,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
