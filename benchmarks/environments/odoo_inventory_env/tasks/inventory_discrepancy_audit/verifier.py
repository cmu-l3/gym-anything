#!/usr/bin/env python3
"""
Verifier for inventory_discrepancy_audit task.

Scoring (100 points total):
- INV-AUDIT-001 (3M OX2000): qty adjusted to 45     → 20 points
- INV-AUDIT-002 (Milwaukee):  qty adjusted to 12     → 20 points
- INV-AUDIT-003 (Stanley):    qty adjusted to 18     → 20 points
- INV-AUDIT-004 (Honeywell):  qty adjusted to 0      → 20 points
- INV-AUDIT-005 (3M N95):     qty adjusted to 50     → 20 points

Pass threshold: 60 points (at least 3 out of 5 discrepant products corrected)
Note: INV-AUDIT-006 is a distractor with no discrepancy; not scored.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_inventory_discrepancy_audit(traj, env_info, task_info):
    """
    Verify that the agent correctly reconciled physical count discrepancies
    across 5 industrial safety product SKUs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_products = metadata.get('products', {})
    pass_threshold = metadata.get('pass_threshold', 60)

    # Discrepant SKUs that should be corrected (INV-AUDIT-006 is the distractor)
    discrepant_skus = metadata.get('discrepant_skus',
        ['INV-AUDIT-001', 'INV-AUDIT-002', 'INV-AUDIT-003', 'INV-AUDIT-004', 'INV-AUDIT-005'])

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env('/tmp/inventory_discrepancy_audit_result.json', temp_path)
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

    # Sanity check: if no products exist at all, setup didn't run
    products_exist = any(
        products_result.get(code, {}).get('product_exists', True)
        for code in discrepant_skus
    )
    if not products_exist:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Task setup did not complete — products not found in database"
        }

    # Check if any changes were made at all (do-nothing detection)
    quant_changes = result.get('quant_changes_after_start', 0)
    if quant_changes == 0:
        # Check product quantities directly — if all still match initial, agent did nothing
        all_unchanged = all(
            not products_result.get(code, {}).get('was_changed', False)
            for code in discrepant_skus
        )
        if all_unchanged:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No inventory adjustments detected — agent made no changes"
            }

    # Score each discrepant product (20 points each)
    points_per_product = 20
    for code in discrepant_skus:
        prod_data = products_result.get(code, {})
        expected_qty = prod_data.get('expected_qty', -1)
        current_qty = prod_data.get('current_qty', -1)
        all_internal_qty = prod_data.get('all_internal_qty', current_qty)
        matches = prod_data.get('matches_expected', False)
        prod_exists = prod_data.get('product_exists', True)

        if not prod_exists:
            subscores[code] = False
            feedback_parts.append(f"{code}: product not found in database")
            continue

        # Accept either WH/Stock qty or total internal qty (in case agent used different location)
        actual_for_check = current_qty
        if not matches and abs(all_internal_qty - expected_qty) < 0.5:
            actual_for_check = all_internal_qty
            matches = True

        if matches:
            score += points_per_product
            subscores[code] = True
            feedback_parts.append(f"{code}: ✓ qty={actual_for_check:.0f} (expected {expected_qty:.0f})")
        else:
            subscores[code] = False
            if current_qty == prod_data.get('initial_qty', -999):
                feedback_parts.append(f"{code}: ✗ qty={current_qty:.0f} (not adjusted, expected {expected_qty:.0f})")
            else:
                feedback_parts.append(f"{code}: ✗ qty={current_qty:.0f} (wrong, expected {expected_qty:.0f})")

    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No adjustments found",
        "subscores": subscores,
        "debug": {
            "quant_changes": result.get('quant_changes_after_start', 0),
            "products_correct": sum(1 for v in subscores.values() if v),
        }
    }
