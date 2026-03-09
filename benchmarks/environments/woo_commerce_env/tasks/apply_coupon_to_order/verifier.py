#!/usr/bin/env python3
"""
Verifier for Apply Coupon to Order task in WooCommerce.

This is a harder, multi-step task requiring the agent to:
1. Navigate to WooCommerce > Orders > Add Order
2. Add specific existing products as line items with correct quantities
3. Apply an existing coupon code
4. Set the customer to an existing customer
5. Save the order

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points):
  1. Order exists (10 pts)
  2. Correct products in order (15 pts) - both products present with right quantities
  3. Coupon applied (15 pts) - WELCOME10 applied with correct discount
  4. Customer assigned (10 pts) - John Doe associated with order
  5. Order totals correct (10 pts) - subtotal, discount, total make sense
  6. Order count increased (10 pts)

VLM checks (30 points):
  7. Process verification (15 pts): trajectory shows multi-step order creation workflow
  8. Final state verification (10 pts): shows order saved/created
  9. Cross-validation (5 pts)

Pass threshold: 55 points AND order found AND coupon applied AND
(VLM confirms workflow OR VLM unavailable)
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a manual order in a WooCommerce store via the WordPress admin interface.

The images are sampled chronologically from the agent's full interaction (earliest to latest).

For successful order creation with coupon application, the agent should:
1. Start at the WordPress admin dashboard (already logged in)
2. Navigate to WooCommerce > Orders section
3. Create a new order (Add Order or New Order button)
4. Add products as line items to the order
5. Apply a coupon code to the order
6. Set a customer for the order
7. Save/Create the order

Assess:
1. WORKFLOW_COMPLETED: Did the agent progress through creating an order with products and a coupon?
2. ORDER_FORM_VISIBLE: Is the WooCommerce order creation/edit form visible at any point?
3. MULTI_STEP_PROGRESSION: Does the agent perform multiple steps (add products, apply coupon, set customer)?
4. SAVE_CONFIRMED: Is there evidence the order was saved?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "order_form_visible": true/false,
    "multi_step_progression": true/false,
    "save_confirmed": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce order creation task.

This is a desktop screenshot showing the WordPress admin interface in a browser.

Assess:
1. ADMIN_VISIBLE: Is the WordPress/WooCommerce admin interface visible?
2. ORDER_VISIBLE: Is an order page visible (order details, line items, totals)?
3. SUCCESS_INDICATORS: Are there success indicators (order created/saved message, order number visible)?
4. ERROR_INDICATORS: Are there error messages?

Respond in JSON format:
{
    "admin_visible": true/false,
    "order_visible": true/false,
    "success_indicators": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_apply_coupon_to_order(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_products = metadata.get('expected_products', [])
    expected_coupon = metadata.get('expected_coupon', 'WELCOME10')
    expected_customer_email = metadata.get('expected_customer_email', 'john.doe@example.com')

    feedback_parts = []
    score = 0
    details = {}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/apply_coupon_to_order_result.json", temp_result.name)
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

    initial_count = result.get('initial_order_count', 0)
    current_count = result.get('current_order_count', 0)
    order_found = result.get('order_found', False)
    order = result.get('order', {})

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # 1. Order exists (10 pts)
    order_status = order.get('status', '')
    # WooCommerce order statuses: wc-pending, wc-processing, wc-on-hold, wc-completed, etc.
    # Also accept without wc- prefix. Auto-draft orders should NOT pass.
    valid_order_statuses = ['wc-pending', 'wc-processing', 'wc-on-hold', 'wc-completed',
                            'pending', 'processing', 'on-hold', 'completed']
    order_status_valid = order_status.strip().lower() in valid_order_statuses if order_status else False

    if order_found:
        score += 10
        feedback_parts.append(f"Order found: #{order.get('id', '?')}")
        if order_status_valid:
            feedback_parts.append(f"Order status valid: {order_status}")
        else:
            feedback_parts.append(f"Order status invalid: '{order_status}' (auto-draft/draft orders are not valid)")
    else:
        feedback_parts.append("Order NOT found")

    # 2. Correct products in order (15 pts)
    line_items = order.get('line_items', [])
    products_correct = 0
    products_found = set()

    for expected in expected_products:
        exp_name = expected.get('name', '').lower()
        exp_sku = expected.get('sku', '').lower()
        exp_qty = int(expected.get('quantity', 0))

        for item in line_items:
            item_name = item.get('name', '').lower()
            item_sku = item.get('sku', '').lower()
            item_qty = int(float(item.get('quantity', 0)))

            if (exp_name in item_name or item_name in exp_name or
                    (exp_sku and exp_sku == item_sku)):
                products_found.add(exp_name)
                if item_qty == exp_qty:
                    products_correct += 1
                    feedback_parts.append(f"Product '{expected['name']}' x{exp_qty}: correct")
                else:
                    feedback_parts.append(f"Product '{expected['name']}' qty mismatch: expected {exp_qty}, got {item_qty}")
                break
        else:
            feedback_parts.append(f"Product '{expected['name']}' NOT found in order")

    total_expected = len(expected_products)
    if products_correct == total_expected:
        score += 15
    elif products_correct > 0:
        score += int(15 * products_correct / total_expected)
    elif len(products_found) > 0:
        score += 5
        feedback_parts.append("Some products found but with wrong quantities")

    # 3. Coupon applied (15 pts)
    coupon_applied = order.get('coupon_applied', '')
    coupon_correct = expected_coupon.lower() in coupon_applied.lower() if coupon_applied else False

    if coupon_correct:
        score += 15
        feedback_parts.append(f"Coupon '{expected_coupon}' applied")
    elif coupon_applied:
        score += 5
        feedback_parts.append(f"Coupon applied but wrong code: expected '{expected_coupon}', got '{coupon_applied}'")
    else:
        feedback_parts.append("No coupon applied")

    # 4. Customer assigned (10 pts)
    customer_email = order.get('customer_email', '')
    customer_correct = customer_email.strip().lower() == expected_customer_email.strip().lower()
    customer_id = order.get('customer_id', '')

    if customer_correct:
        score += 10
        feedback_parts.append(f"Customer correct: {expected_customer_email}")
    elif customer_id and customer_id != '0':
        score += 5
        feedback_parts.append(f"Customer assigned but different: expected '{expected_customer_email}', got '{customer_email}'")
    else:
        feedback_parts.append("No customer assigned to order")

    # 5. Order totals correct (10 pts)
    order_total = order.get('total', '')
    order_discount = order.get('discount', '')
    order_subtotal = order.get('subtotal', '')

    totals_valid = False
    try:
        if order_total and order_discount and order_subtotal:
            total_f = float(order_total)
            discount_f = float(order_discount)
            subtotal_f = float(order_subtotal)

            # Check discount is approximately 10% of subtotal
            expected_discount = subtotal_f * 0.10
            if abs(discount_f - expected_discount) < 1.0:
                score += 10
                totals_valid = True
                feedback_parts.append(f"Order totals valid: subtotal=${order_subtotal}, discount=${order_discount}, total=${order_total}")
            elif discount_f > 0:
                score += 5
                feedback_parts.append(f"Discount applied but amount unexpected: ${order_discount} (expected ~${expected_discount:.2f})")
            else:
                feedback_parts.append("No discount amount recorded")
        elif order_total:
            score += 3
            feedback_parts.append(f"Order total recorded: ${order_total} but discount/subtotal missing")
    except (ValueError, TypeError):
        feedback_parts.append("Order totals could not be verified")

    # 6. Order count increased (10 pts)
    if current_count > initial_count:
        score += 10
        feedback_parts.append("Order count increased (new order created)")
    else:
        feedback_parts.append("Order count unchanged")

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
                multi_step = process_result.get('multi_step_progression', False)
                form_visible = process_result.get('order_form_visible', False)
                if workflow_ok and multi_step:
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Multi-step order workflow confirmed")
                elif workflow_ok or form_visible:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Order workflow partially confirmed")
                elif multi_step:
                    score += 5
                    feedback_parts.append("VLM process: Multi-step progression seen")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")

        if has_final:
            final_result = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
            details['vlm_final_state'] = final_result
            if final_result:
                admin_ok = final_result.get('admin_visible', False)
                order_ok = final_result.get('order_visible', False)
                success_ok = final_result.get('success_indicators', False)
                if admin_ok and order_ok and success_ok:
                    score += 10
                    feedback_parts.append("VLM final: Order page with success indicators")
                elif admin_ok and order_ok:
                    score += 7
                    feedback_parts.append("VLM final: Order page visible")
                elif admin_ok:
                    score += 4
                    feedback_parts.append("VLM final: Admin visible")

        if order_found and coupon_correct and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: Order + coupon + VLM agree")
            details['cross_validation'] = 'pass'
        elif order_found and coupon_correct:
            details['cross_validation'] = 'mismatch'
        else:
            details['cross_validation'] = 'neither'
    else:
        feedback_parts.append("VLM checks skipped (unavailable)")

    # ================================================================
    # PASS CRITERIA
    # ================================================================
    # Order must exist, have valid status, correct coupon, and meet score threshold
    if vlm_available:
        passed = score >= 55 and order_found and order_status_valid and coupon_correct and vlm_workflow_confirmed
    else:
        passed = score >= 55 and order_found and order_status_valid and coupon_correct

    details.update({
        "order_found": order_found,
        "order_status_valid": order_status_valid,
        "products_correct": products_correct,
        "coupon_correct": coupon_correct,
        "customer_correct": customer_correct,
        "totals_valid": totals_valid,
        "vlm_available": vlm_available,
        "vlm_workflow_confirmed": vlm_workflow_confirmed,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
