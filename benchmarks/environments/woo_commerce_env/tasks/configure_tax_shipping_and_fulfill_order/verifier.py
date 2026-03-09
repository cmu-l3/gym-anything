#!/usr/bin/env python3
"""
Verifier for Configure Tax, Shipping, and Fulfill Order task in WooCommerce.

This is a very_hard task requiring the agent to:
1. Enable tax calculations in WooCommerce settings
2. Add a CA tax rate of 8.25%
3. Create a California shipping zone with flat-rate shipping
4. Create an order with specific products, customer, billing state, note, and status

Verification Strategy (Hybrid: Programmatic + VLM):

Programmatic checks (70 points):
  1. Taxes enabled in settings (5 pts)
  2. CA tax rate exists with correct rate (10 pts)
  3. Shipping zone 'California' exists (5 pts)
  4. Flat rate shipping method with ~$7.99 cost (5 pts)
  5. Order exists with correct products/quantities (15 pts)
  6. Order assigned to Jane Smith (5 pts)
  7. Order billing state is CA (5 pts)
  8. Order status is 'processing' (5 pts)
  9. Order note contains expected text (10 pts)
  10. Order count increased (5 pts)

VLM checks (30 points):
  11. Process verification (15 pts)
  12. Final state verification (10 pts)
  13. Cross-validation (5 pts)

Pass threshold: 50 points AND tax rate exists AND order found AND order has correct status
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring tax rates, shipping zones, and creating an order in WooCommerce via the WordPress admin interface.

The images are sampled chronologically (earliest to latest).

For success, the agent should work across multiple WooCommerce settings areas:
1. WooCommerce > Settings > General (enable taxes)
2. WooCommerce > Settings > Tax (add tax rates)
3. WooCommerce > Settings > Shipping (create shipping zones)
4. WooCommerce > Orders > Add Order (create and configure an order)

Assess:
1. WORKFLOW_COMPLETED: Did the agent work across multiple WooCommerce admin areas?
2. SETTINGS_PAGES: Did the agent visit WooCommerce settings pages (Tax, Shipping)?
3. ORDER_CREATION: Did the agent navigate to order creation and fill in details?
4. MULTI_AREA_PROGRESSION: Do frames show progression across different admin sections?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "settings_pages": true/false,
    "order_creation": true/false,
    "multi_area_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce tax/shipping/order configuration task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress/WooCommerce admin interface visible?
2. SUCCESS_INDICATORS: Are there success indicators (saved settings, order created)?
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


def verify_configure_tax_shipping_and_fulfill_order(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_products = metadata.get('order_products', [])
    expected_customer = metadata.get('order_customer_email', 'jane.smith@example.com')
    expected_note = metadata.get('order_note', 'Priority fulfillment')

    feedback_parts = []
    score = 0
    details = {}

    # Load result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/tax_shipping_order_result.json", temp_result.name)
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

    # 1. Taxes enabled (5 pts)
    taxes_enabled = result.get('taxes_enabled', '') == 'yes'
    if taxes_enabled:
        score += 5
        feedback_parts.append("Taxes enabled")
    else:
        feedback_parts.append(f"Taxes NOT enabled (value: '{result.get('taxes_enabled', '')}')")

    # 2. CA tax rate exists with correct rate (10 pts)
    tax_rate_exists = result.get('tax_rate_exists', False)
    tax_rate_data = result.get('tax_rate', {})
    tax_rate_correct = False

    if tax_rate_exists:
        rate_val = tax_rate_data.get('rate', '')
        try:
            rate_float = float(rate_val)
            if abs(rate_float - 8.25) < 0.01:
                score += 10
                tax_rate_correct = True
                feedback_parts.append("CA tax rate correct (8.25%)")
            else:
                score += 5
                feedback_parts.append(f"CA tax rate exists but wrong: expected 8.25%, got {rate_val}%")
        except (ValueError, TypeError):
            score += 3
            feedback_parts.append(f"CA tax rate exists but value not parseable: '{rate_val}'")
    else:
        feedback_parts.append("CA tax rate NOT found")

    # 3. Shipping zone 'California' exists (5 pts)
    shipping_zone_exists = result.get('shipping_zone_exists', False)
    if shipping_zone_exists:
        score += 5
        feedback_parts.append("Shipping zone 'California' exists")
    else:
        feedback_parts.append("Shipping zone 'California' NOT found")

    # 4. Flat rate shipping method (5 pts)
    shipping_data = result.get('shipping_zone', {})
    flat_rate_exists = shipping_data.get('flat_rate_exists', False)
    flat_rate_settings = shipping_data.get('flat_rate_settings', '')
    flat_rate_cost_ok = False

    if flat_rate_exists:
        # The settings are stored as a serialized PHP array; check for 7.99
        if '7.99' in str(flat_rate_settings):
            score += 5
            flat_rate_cost_ok = True
            feedback_parts.append("Flat rate shipping $7.99 configured")
        else:
            score += 3
            feedback_parts.append(f"Flat rate exists but cost may differ (settings: {flat_rate_settings[:100]})")
    else:
        feedback_parts.append("Flat rate shipping NOT found in California zone")

    # 5. Order exists with correct products/quantities (15 pts)
    order_found = result.get('order_found', False)
    order = result.get('order', {})
    line_items = order.get('line_items', [])

    products_correct = 0
    for expected in expected_products:
        exp_name = expected['name'].lower()
        exp_sku = expected.get('sku', '').lower()
        exp_qty = int(expected['quantity'])

        for item in line_items:
            item_name = item.get('name', '').lower()
            item_sku = item.get('sku', '').lower()
            item_qty = int(float(item.get('quantity', 0)))

            if (exp_name in item_name or item_name in exp_name or
                    (exp_sku and exp_sku == item_sku)):
                if item_qty == exp_qty:
                    products_correct += 1
                    feedback_parts.append(f"Product '{expected['name']}' x{exp_qty}: correct")
                else:
                    feedback_parts.append(f"Product '{expected['name']}' qty wrong: expected {exp_qty}, got {item_qty}")
                break
        else:
            feedback_parts.append(f"Product '{expected['name']}' NOT found in order")

    total_expected = len(expected_products)
    if products_correct == total_expected:
        score += 15
    elif products_correct > 0:
        score += int(15 * products_correct / total_expected)

    # 6. Order assigned to Jane Smith (5 pts)
    customer_email = order.get('customer_email', '').lower().strip()
    customer_ok = customer_email == expected_customer.lower()
    if customer_ok:
        score += 5
        feedback_parts.append("Customer: Jane Smith")
    elif customer_email:
        feedback_parts.append(f"Customer mismatch: expected {expected_customer}, got {customer_email}")
    else:
        feedback_parts.append("No customer assigned")

    # 7. Order billing state is CA (5 pts)
    billing_state = order.get('billing_state', '').upper().strip()
    billing_ok = billing_state == 'CA'
    if billing_ok:
        score += 5
        feedback_parts.append("Billing state: CA")
    elif billing_state:
        feedback_parts.append(f"Billing state mismatch: expected CA, got {billing_state}")
    else:
        feedback_parts.append("Billing state not set")

    # 8. Order status is 'processing' (5 pts)
    order_status = order.get('status', '').lower().strip()
    valid_processing = order_status in ('wc-processing', 'processing')
    if valid_processing:
        score += 5
        feedback_parts.append("Order status: processing")
    elif order_status:
        feedback_parts.append(f"Order status wrong: expected 'processing', got '{order_status}'")
    else:
        feedback_parts.append("Order status not set")

    # 9. Order note contains expected text (10 pts)
    note_found = order.get('note_found', False)
    note_text = order.get('note_text', '').lower()
    note_ok = False

    if note_found and 'priority fulfillment' in note_text:
        score += 10
        note_ok = True
        feedback_parts.append("Order note correct")
    elif note_found and 'loyalty' in note_text:
        score += 7
        note_ok = True
        feedback_parts.append("Order note partially matches")
    elif note_found:
        score += 3
        feedback_parts.append(f"Order note exists but content differs")
    else:
        feedback_parts.append("No order note found")

    # 10. Order count increased (5 pts)
    initial_count = result.get('initial_order_count', 0)
    current_count = result.get('current_order_count', 0)
    if current_count > initial_count:
        score += 5
        feedback_parts.append("Order count increased")
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
                settings_ok = process_result.get('settings_pages', False)
                order_ok = process_result.get('order_creation', False)
                if workflow_ok and (settings_ok or order_ok):
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Multi-area workflow confirmed")
                elif workflow_ok:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Workflow confirmed")
                elif settings_ok or order_ok:
                    score += 5
                    feedback_parts.append("VLM process: Partial progress")
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

        if tax_rate_exists and order_found and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: Tax + order + VLM agree")
            details['cross_validation'] = 'pass'
        else:
            details['cross_validation'] = 'partial' if vlm_workflow_confirmed else 'neither'
    else:
        feedback_parts.append("VLM checks skipped (unavailable)")

    # ================================================================
    # PASS CRITERIA
    # ================================================================
    if vlm_available:
        passed = score >= 50 and tax_rate_exists and order_found and valid_processing and vlm_workflow_confirmed
    else:
        passed = score >= 50 and tax_rate_exists and order_found and valid_processing

    details.update({
        "taxes_enabled": taxes_enabled,
        "tax_rate_exists": tax_rate_exists,
        "tax_rate_correct": tax_rate_correct,
        "shipping_zone_exists": shipping_zone_exists,
        "flat_rate_cost_ok": flat_rate_cost_ok,
        "order_found": order_found,
        "products_correct": products_correct,
        "customer_ok": customer_ok,
        "billing_ok": billing_ok,
        "valid_processing": valid_processing,
        "note_ok": note_ok,
        "vlm_available": vlm_available,
        "vlm_workflow_confirmed": vlm_workflow_confirmed,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
