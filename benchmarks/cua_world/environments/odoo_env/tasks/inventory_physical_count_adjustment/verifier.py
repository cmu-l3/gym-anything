#!/usr/bin/env python3
"""
Verifier for inventory_physical_count_adjustment task.

Scoring (100 points total):
- Inventory adjustment correct for all 3 products: 45 pts (15 each)
- Reorder rules created for all 3 products with correct min qty (15): 30 pts (10 each)
- Reorder rules have correct max qty (60): 25 pts (split across products)

Pass threshold: 65 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_inventory_physical_count_adjustment(traj, env_info, task_info):
    """
    Verify that the agent correctly performed physical inventory adjustment
    and set up reorder rules for all 3 products.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        try:
            copy_from_env('/tmp/inventory_physical_count_adjustment_result.json', temp_file.name)
        except FileNotFoundError:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found — export script may not have run",
            }
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        try:
            with open(temp_file.name) as f:
                result = json.load(f)
        except json.JSONDecodeError as e:
            return {"passed": False, "score": 0, "feedback": f"Result file is not valid JSON: {e}"}
    finally:
        os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Setup/export error: {result.get('error')}"}

    products = result.get('products', [])
    if not products:
        return {"passed": False, "score": 0, "feedback": "No product data in result"}

    score = 0
    feedback_parts = []
    subscores = {}

    # ─── Criterion 1: Physical inventory adjustments (45 pts total, 15 per product) ─
    adjusted_count = 0
    for prod in products:
        name = prod.get('name', 'Unknown product')
        if prod.get('qty_correct'):
            score += 15
            adjusted_count += 1
            feedback_parts.append(
                f"✓ {name}: adjusted to {prod.get('expected_physical_qty')} units (15/15)"
            )
        elif prod.get('qty_changed'):
            # Changed but not to the right value — partial credit
            score += 5
            feedback_parts.append(
                f"~ {name}: quantity changed but incorrect "
                f"(expected {prod.get('expected_physical_qty')}, "
                f"current {prod.get('current_qty', '?')}) (5/15)"
            )
        else:
            feedback_parts.append(
                f"✗ {name}: system qty unchanged at {prod.get('original_system_qty')} "
                f"(expected {prod.get('expected_physical_qty')}) (0/15)"
            )

    subscores['inventory_adjusted'] = adjusted_count
    subscores['inventory_adjusted_all'] = (adjusted_count == 3)

    # ─── Criterion 2: Reorder rules created with correct min qty (30 pts, 10 each) ─
    reorder_min_count = 0
    for prod in products:
        name = prod.get('name', 'Unknown product')
        if prod.get('reorder_min_correct'):
            score += 10
            reorder_min_count += 1
        elif prod.get('has_reorder_rule'):
            # Rule exists but wrong min qty — partial
            score += 3
            feedback_parts.append(
                f"~ {name}: reorder rule exists but min qty incorrect (expected 15) (3/10)"
            )
        else:
            feedback_parts.append(f"✗ {name}: no reorder rule created (0/10)")

    if reorder_min_count > 0:
        feedback_parts.append(
            f"Reorder rules with correct min=15: {reorder_min_count}/3 products ({reorder_min_count*10}/30)"
        )
    subscores['reorder_rules_min_correct'] = reorder_min_count

    # ─── Criterion 3: Reorder rules with correct max qty (25 pts split) ──────
    reorder_max_count = 0
    for prod in products:
        if prod.get('reorder_max_correct'):
            score += 8
            reorder_max_count += 1

    # Remaining 1 pt for having all 3 fully correct
    if reorder_max_count == 3:
        score += 1

    if reorder_max_count > 0:
        feedback_parts.append(
            f"Reorder rules with correct max=60: {reorder_max_count}/3 products "
            f"({reorder_max_count * 8 + (1 if reorder_max_count == 3 else 0)}/25)"
        )
    subscores['reorder_rules_max_correct'] = reorder_max_count

    # Clamp score
    score = min(score, 100)
    passed = score >= 65

    if not feedback_parts:
        feedback_parts.append("No adjustments or reorder rules detected")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "debug": {
            "products_adjusted_correctly": result.get('products_adjusted_correctly'),
            "products_with_full_correct_reorder": result.get('products_with_full_correct_reorder'),
        },
    }
