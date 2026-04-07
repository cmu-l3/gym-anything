#!/usr/bin/env python3
"""Verifier for Seasonal Product Launch & Fulfillment task in Magento.

Task: Create a configurable product with shirt_size attribute, set up a cart
price rule with coupon, place an admin phone order using the product and coupon,
then invoice and ship the order.

Scored on multiple criteria (100 pts). Pass threshold: 60 pts.

NOTE: This is a stub verifier. Primary verification is done via VLM checklist.
The programmatic scoring below provides supplementary signal from database state.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_seasonal_launch(traj, env_info, task_info):
    """
    Verify the seasonal product launch and fulfillment task.

    Criteria and scoring (100 pts total, pass threshold 60):

    Phase 1 - Product Attribute (10 pts):
      1a. Attribute 'shirt_size' exists as dropdown (select) type   (5 pts)
      1b. Attribute has all 4 options: S, M, L, XL                  (5 pts)

    Phase 2 - Configurable Product (25 pts):
      2a. Product SHIRT-LINEN-001 exists, type=configurable         (10 pts)
      2b. Product name and price correct                            (5 pts)
      2c. Product in Clothing category                              (5 pts)
      2d. 4 linked simple variants with qty ~50                     (5 pts)

    Phase 3 - Cart Price Rule (20 pts):
      3a. Rule 'Summer Checkout Bonus' exists and active            (8 pts)
      3b. Flat $25 discount, subtotal >= $200 condition             (7 pts)
      3c. Coupon SUMMER25 exists, 1 use/customer                    (5 pts)

    Phase 4 - Order (25 pts):
      4a. Order exists for john.doe@example.com (created during task)(10 pts)
      4b. Order contains correct products                           (10 pts)
      4c. Coupon SUMMER25 applied to order                          (5 pts)

    Phase 5 - Fulfillment (20 pts):
      5a. Invoice created for the order                             (10 pts)
      5b. Shipment with tracking UPS1Z2025SUMMER0001                (10 pts)
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/seasonal_launch_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found - export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []

    # ── Phase 1: Product Attribute (10 pts) ──────────────────────────────────

    # 1a. Attribute exists as dropdown (5 pts)
    attr_found = result.get('attribute_found', False)
    attr_input = result.get('attribute_input', '')

    if attr_found and attr_input == 'select':
        score += 5
        feedback_parts.append("Attribute 'shirt_size' created as dropdown (5/5)")
    elif attr_found:
        score += 2
        feedback_parts.append(f"Attribute exists but wrong type: {attr_input} (2/5)")
    else:
        feedback_parts.append("Attribute 'shirt_size' NOT found (0/5)")

    # 1b. Attribute options (5 pts)
    options_count = result.get('options_found_count', 0)
    if options_count >= 4:
        score += 5
        feedback_parts.append("All 4 size options found (5/5)")
    elif options_count > 0:
        partial = options_count  # 1 pt per option found
        score += partial
        feedback_parts.append(f"Partial options: {options_count}/4 ({partial}/5)")
    else:
        feedback_parts.append("No size options found (0/5)")

    # ── Phase 2: Configurable Product (25 pts) ──────────────────────────────

    # 2a. Product exists as configurable (10 pts)
    prod_found = result.get('product_found', False)
    prod_type = result.get('product_type', '')

    if prod_found and prod_type == 'configurable':
        score += 10
        feedback_parts.append("Configurable product SHIRT-LINEN-001 created (10/10)")
    elif prod_found:
        score += 5
        feedback_parts.append(f"Product exists but type={prod_type} (5/10)")
    else:
        feedback_parts.append("Product SHIRT-LINEN-001 NOT found (0/10)")

    # 2b. Name and price (5 pts)
    if prod_found:
        name = result.get('product_name', '')
        name_ok = 'linen resort shirt' in name.lower()

        try:
            price = float(result.get('product_price', 0))
            price_ok = abs(price - 79.99) < 0.10
        except (ValueError, TypeError):
            price_ok = False

        if name_ok and price_ok:
            score += 5
            feedback_parts.append("Name and price correct (5/5)")
        elif name_ok or price_ok:
            score += 3
            feedback_parts.append(f"Partial: name={'OK' if name_ok else name}, price={'OK' if price_ok else result.get('product_price')} (3/5)")
        else:
            feedback_parts.append(f"Name/price wrong: '{name}' / {result.get('product_price')} (0/5)")

    # 2c. Category (5 pts)
    if prod_found:
        cat = result.get('product_category', '')
        if 'Clothing' in cat:
            score += 5
            feedback_parts.append("Category Clothing assigned (5/5)")
        else:
            feedback_parts.append("Category not assigned to Clothing (0/5)")

    # 2d. Variants (5 pts)
    variant_count = result.get('variant_count', 0)
    variant_qty_ok = result.get('variant_qty_ok', 0)

    if variant_count >= 4 and variant_qty_ok >= 4:
        score += 5
        feedback_parts.append(f"4 variants with correct qty (5/5)")
    elif variant_count >= 4:
        score += 3
        feedback_parts.append(f"4 variants linked but qty issues ({variant_qty_ok}/4 correct) (3/5)")
    elif variant_count > 0:
        score += 1
        feedback_parts.append(f"Partial variants: {variant_count}/4 (1/5)")
    else:
        feedback_parts.append("No variants linked (0/5)")

    # ── Phase 3: Cart Price Rule (20 pts) ────────────────────────────────────

    # 3a. Rule exists and active (8 pts)
    rule_found = result.get('rule_found', False)
    rule_active = str(result.get('rule_active', '0')).strip()

    if rule_found and rule_active == '1':
        score += 8
        feedback_parts.append("Cart rule 'Summer Checkout Bonus' active (8/8)")
    elif rule_found:
        score += 4
        feedback_parts.append("Cart rule exists but not active (4/8)")
    else:
        feedback_parts.append("Cart rule 'Summer Checkout Bonus' NOT found (0/8)")

    # 3b. Discount and condition (7 pts)
    if rule_found:
        discount_type = result.get('discount_type', '').strip().lower()
        try:
            discount_amount = float(result.get('discount_amount', 0))
        except (ValueError, TypeError):
            discount_amount = 0.0

        has_subtotal = result.get('has_subtotal_condition', False)
        subtotal_value = result.get('subtotal_value', '')

        type_ok = discount_type in ('by_fixed', 'cart_fixed')
        amount_ok = abs(discount_amount - 25.0) < 0.01
        subtotal_ok = has_subtotal and subtotal_value == '200'

        pts = 0
        if type_ok and amount_ok:
            pts += 4
        elif amount_ok:
            pts += 2
        if subtotal_ok:
            pts += 3
        elif has_subtotal:
            pts += 1
        score += pts
        feedback_parts.append(f"Discount: type={discount_type} amt={discount_amount} subtotal={subtotal_value} ({pts}/7)")

    # 3c. Coupon (5 pts)
    if rule_found:
        coupon_found = result.get('coupon_found', False)
        uses_per_customer = str(result.get('uses_per_customer', '')).strip()

        if coupon_found and uses_per_customer == '1':
            score += 5
            feedback_parts.append("Coupon SUMMER25 with 1 use/customer (5/5)")
        elif coupon_found:
            score += 3
            feedback_parts.append(f"Coupon SUMMER25 found but uses_per_customer={uses_per_customer} (3/5)")
        else:
            feedback_parts.append("Coupon SUMMER25 NOT found (0/5)")

    # ── Phase 4: Order (25 pts) ──────────────────────────────────────────────

    # 4a. Order exists (10 pts)
    order_found = result.get('order_found', False)

    if order_found:
        score += 10
        feedback_parts.append("Order for john.doe@example.com created during task (10/10)")
    else:
        feedback_parts.append("No order found for john.doe@example.com during task (0/10)")

    # 4b. Correct products (10 pts)
    if order_found:
        has_shirt = result.get('order_has_shirt', False)
        has_jacket = result.get('order_has_jacket', False)

        pts = 0
        if has_shirt:
            pts += 5
        if has_jacket:
            pts += 5
        score += pts
        feedback_parts.append(f"Order items: shirt={has_shirt} jacket={has_jacket} ({pts}/10)")

    # 4c. Coupon applied (5 pts)
    if order_found:
        order_coupon = str(result.get('order_coupon', '')).strip().upper()
        if order_coupon == 'SUMMER25':
            score += 5
            feedback_parts.append("Coupon SUMMER25 applied to order (5/5)")
        else:
            feedback_parts.append(f"Order coupon: '{order_coupon}' (expected SUMMER25) (0/5)")

    # ── Phase 5: Fulfillment (20 pts) ────────────────────────────────────────

    # 5a. Invoice (10 pts)
    invoice_found = result.get('invoice_found', False)
    if invoice_found:
        score += 10
        feedback_parts.append("Invoice created (10/10)")
    else:
        feedback_parts.append("No invoice found (0/10)")

    # 5b. Shipment with tracking (10 pts)
    shipment_found = result.get('shipment_found', False)
    tracking = str(result.get('tracking_number', '')).strip()

    if shipment_found and tracking == 'UPS1Z2025SUMMER0001':
        score += 10
        feedback_parts.append("Shipment with correct tracking number (10/10)")
    elif shipment_found:
        score += 4
        feedback_parts.append(f"Shipment exists but tracking='{tracking}' (4/10)")
    else:
        feedback_parts.append("No shipment found (0/10)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
