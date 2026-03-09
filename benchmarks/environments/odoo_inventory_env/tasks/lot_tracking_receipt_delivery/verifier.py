#!/usr/bin/env python3
"""
Verifier for lot_tracking_receipt_delivery task.

Scoring (100 points total):
- 10 pts each: Lot tracking enabled on LOT-TRACK-001, 002, 003 (30 pts total)
- 30 pts: Receipt validated (picking state = 'done')
- 10 pts each: Correct lot number assigned for each product (30 pts total)
- 10 pts total: Correct quantities received across all products
  (partial: 3-4 pts each if qty matches for individual product)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_lot_tracking_receipt_delivery(traj, env_info, task_info):
    """
    Verify that the agent enabled lot tracking on all 3 medical products
    and validated the PO receipt with the correct lot numbers and quantities.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_products = metadata.get('products', {
        'LOT-TRACK-001': {'qty': 200, 'lot': 'MED-2024-AB-001'},
        'LOT-TRACK-002': {'qty': 150, 'lot': 'MED-2024-BR-001'},
        'LOT-TRACK-003': {'qty': 300, 'lot': 'MED-2024-3M-001'},
    })
    pass_threshold = metadata.get('pass_threshold', 60)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env('/tmp/lot_tracking_receipt_delivery_result.json', temp_path)
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
    receipt_validated = result.get('receipt_validated', False)

    # Do-nothing detection
    any_tracking_enabled = any(
        products_result.get(code, {}).get('tracking_enabled', False)
        for code in expected_products
    )
    if not any_tracking_enabled and not receipt_validated:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No changes detected — lot tracking not enabled and receipt not validated"
        }

    # Criterion 1: Lot tracking enabled on each product (10 pts each)
    tracking_count = 0
    for code in expected_products:
        prod = products_result.get(code, {})
        if prod.get('tracking_enabled', False):
            score += 10
            tracking_count += 1
            subscores[f'tracking_{code}'] = True
            feedback_parts.append(f"{code}: lot tracking enabled (+10)")
        else:
            subscores[f'tracking_{code}'] = False
            actual = prod.get('tracking', 'none')
            feedback_parts.append(f"{code}: tracking={actual!r} (expected 'lot')")

    # Criterion 2: Receipt validated (30 pts)
    if receipt_validated:
        score += 30
        subscores['receipt_validated'] = True
        feedback_parts.append(
            f"Receipt validated (picking={result.get('picking_name', '')}) (+30)"
        )
    else:
        subscores['receipt_validated'] = False
        state = result.get('picking_state', 'not_found')
        feedback_parts.append(f"Receipt not validated (state={state!r})")

    # Criterion 3: Correct lot numbers (10 pts each, only if receipt done)
    if receipt_validated:
        for code, prod_info in expected_products.items():
            expected_lot = prod_info['lot']
            prod = products_result.get(code, {})
            actual_lot = prod.get('lot_received', '')
            if prod.get('correct_lot', False):
                score += 10
                subscores[f'lot_{code}'] = True
                feedback_parts.append(f"{code}: correct lot {actual_lot!r} (+10)")
            else:
                subscores[f'lot_{code}'] = False
                feedback_parts.append(
                    f"{code}: wrong lot {actual_lot!r} (expected {expected_lot!r})"
                )

        # Criterion 4: Correct quantities (10 pts total, ~3 pts each)
        correct_qtys = 0
        qty_details = []
        for code, prod_info in expected_products.items():
            prod = products_result.get(code, {})
            if prod.get('correct_qty', False):
                correct_qtys += 1
                qty_details.append(f"{code}:{prod.get('qty_received', 0):.0f}✓")
            else:
                qty_details.append(
                    f"{code}:{prod.get('qty_received', 0):.0f}✗(exp {prod_info['qty']})"
                )

        qty_score = (correct_qtys * 10) // len(expected_products)
        score += qty_score
        subscores['correct_quantities'] = correct_qtys == len(expected_products)
        if qty_score > 0:
            feedback_parts.append(f"Quantities: {', '.join(qty_details)} (+{qty_score})")
        else:
            feedback_parts.append(f"Quantities incorrect: {', '.join(qty_details)}")
    else:
        for code in expected_products:
            subscores[f'lot_{code}'] = False
        subscores['correct_quantities'] = False
        feedback_parts.append("Lots and quantities not verified — receipt not done")

    score = max(0, score)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No actions detected",
        "subscores": subscores,
        "debug": {
            "tracking_enabled_count": tracking_count,
            "receipt_validated": receipt_validated,
            "picking_state": result.get('picking_state', 'unknown'),
            "po_state": result.get('po_state', 'unknown'),
        }
    }
