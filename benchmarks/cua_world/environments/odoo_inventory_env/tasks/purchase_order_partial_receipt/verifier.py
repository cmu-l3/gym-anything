#!/usr/bin/env python3
"""
Verifier for purchase_order_partial_receipt task.

Scoring (100 points total):
- 15 pts each: Correct vendor chosen for ELEC-COMP-001, 002, 003 (45 pts)
- 10 pts each: Receipt validated (picking done) for each product (30 pts)
- 15 pts: Backorders created for ELEC-COMP-001 and ELEC-COMP-003 (7.5 pts each)
- 10 pts: Correct quantities received (partial: ELEC-COMP-001=40, -002=200, -003=600)

Pass threshold: 55 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_purchase_order_partial_receipt(traj, env_info, task_info):
    """
    Verify that the agent:
    1. Selected the cheapest vendor for each product
    2. Created purchase orders with those vendors
    3. Validated partial receipts
    4. Created backorders for incomplete deliveries
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_products = metadata.get('products', {})
    pass_threshold = metadata.get('pass_threshold', 55)

    # Defaults if metadata missing
    if not expected_products:
        expected_products = {
            'ELEC-COMP-001': {
                'cheapest_vendor': 'Automation Parts Direct',
                'partial_receipt_qty': 40,
                'total_qty': 100,
            },
            'ELEC-COMP-002': {
                'cheapest_vendor': 'Component World',
                'partial_receipt_qty': 200,
                'total_qty': 200,
            },
            'ELEC-COMP-003': {
                'cheapest_vendor': 'Component World',
                'partial_receipt_qty': 600,
                'total_qty': 1000,
            },
        }

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env('/tmp/purchase_order_partial_receipt_result.json', temp_path)
            with open(temp_path, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}
    products_result = result.get('products', {})

    # Do-nothing detection
    any_po_created = any(
        products_result.get(code, {}).get('po_id') is not None
        for code in expected_products
    )
    if not any_po_created:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No purchase orders created after task start — agent made no changes"
        }

    # Criterion 1: Correct vendor selection (15 pts each)
    for code, prod_info in expected_products.items():
        prod = products_result.get(code, {})
        correct_vendor = prod.get('correct_vendor', False)
        vendor_name = prod.get('vendor_name', 'none')
        cheapest = prod_info.get('cheapest_vendor', '')
        if correct_vendor:
            score += 15
            subscores[f'vendor_{code}'] = True
            feedback_parts.append(f"{code}: correct vendor {vendor_name!r} (+15)")
        elif prod.get('po_id'):
            subscores[f'vendor_{code}'] = False
            feedback_parts.append(
                f"{code}: wrong vendor {vendor_name!r} (expected {cheapest!r})"
            )
        else:
            subscores[f'vendor_{code}'] = False
            feedback_parts.append(f"{code}: no PO created")

    # Criterion 2: Receipt validated (10 pts each)
    for code in expected_products:
        prod = products_result.get(code, {})
        has_done = prod.get('has_done_receipt', False)
        if has_done:
            score += 10
            subscores[f'receipt_{code}'] = True
            feedback_parts.append(f"{code}: receipt validated (+10)")
        else:
            subscores[f'receipt_{code}'] = False
            pickings = prod.get('pickings', [])
            states = [p['state'] for p in pickings]
            feedback_parts.append(
                f"{code}: receipt not validated (picking states: {states})"
            )

    # Criterion 3: Backorders (15 pts total — 7.5 pts each for ELEC-COMP-001 and ELEC-COMP-003)
    backorder_products = ['ELEC-COMP-001', 'ELEC-COMP-003']
    backorders_correct = 0
    for code in backorder_products:
        prod = products_result.get(code, {})
        expected_partial = expected_products.get(code, {}).get('partial_receipt_qty', 0)
        total = expected_products.get(code, {}).get('total_qty', 0)
        is_partial = expected_partial < total

        if is_partial and prod.get('has_backorder', False):
            backorders_correct += 1
            feedback_parts.append(f"{code}: backorder created ✓")
        elif is_partial and prod.get('has_done_receipt', False):
            feedback_parts.append(f"{code}: receipt done but no backorder found")
        elif not is_partial:
            backorders_correct += 1  # full receipt — no backorder needed
        else:
            feedback_parts.append(f"{code}: backorder not created")

    backorder_score = int(backorders_correct * 7.5)
    score += backorder_score
    subscores['backorders'] = backorders_correct == len(backorder_products)
    if backorder_score > 0:
        feedback_parts.append(f"Backorders: {backorders_correct}/{len(backorder_products)} (+{backorder_score})")

    # Criterion 4: Correct partial quantities (10 pts total)
    correct_qtys = 0
    qty_details = []
    for code, prod_info in expected_products.items():
        prod = products_result.get(code, {})
        expected_partial = prod_info.get('partial_receipt_qty', 0)
        received = prod.get('qty_received', 0.0)
        if abs(received - expected_partial) < 0.5:
            correct_qtys += 1
            qty_details.append(f"{code}:{received:.0f}✓")
        else:
            qty_details.append(f"{code}:{received:.0f}✗(exp {expected_partial})")

    qty_score = (correct_qtys * 10) // len(expected_products)
    score += qty_score
    subscores['correct_quantities'] = correct_qtys == len(expected_products)
    if qty_score > 0:
        feedback_parts.append(f"Quantities: {', '.join(qty_details)} (+{qty_score})")
    else:
        feedback_parts.append(f"Quantities: {', '.join(qty_details)}")

    score = max(0, score)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No actions detected",
        "subscores": subscores,
        "debug": {
            "pos_created": sum(1 for code in expected_products
                               if products_result.get(code, {}).get('po_id')),
            "correct_vendors": sum(1 for code in expected_products
                                   if products_result.get(code, {}).get('correct_vendor')),
            "receipts_done": sum(1 for code in expected_products
                                 if products_result.get(code, {}).get('has_done_receipt')),
            "backorders_created": backorders_correct,
        }
    }
