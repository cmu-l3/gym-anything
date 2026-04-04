#!/usr/bin/env python3
"""
Verifier for three_step_delivery_fulfillment task.

Scoring (100 points total):
- 20 pts: Warehouse configured for 3-step delivery (pick_pack_ship)
- 15 pts: Sales order created for TechSource Procurement LLC
- 15 pts: Pick operation completed (done)
- 15 pts: Pack operation completed (done)
- 20 pts: Ship/delivery operation completed (done)
- 15 pts: Correct quantities shipped (3STEP-001: 20, 3STEP-002: 15, 3STEP-003: 10)

Pass threshold: 65 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_three_step_delivery_fulfillment(traj, env_info, task_info):
    """
    Verify that the agent configured 3-step delivery, created a sales order
    for TechSource Procurement LLC, and completed all three warehouse operations.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    customer = metadata.get('customer', 'TechSource Procurement LLC')
    expected_products = metadata.get('products', {
        '3STEP-001': {'qty': 20},
        '3STEP-002': {'qty': 15},
        '3STEP-003': {'qty': 10},
    })
    pass_threshold = metadata.get('pass_threshold', 65)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env('/tmp/three_step_delivery_fulfillment_result.json', temp_path)
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

    delivery_steps = result.get('delivery_steps', 'ship_only')
    so_id = result.get('so_id')
    so_state = result.get('so_state', '')
    pick_op_done = result.get('pick_op_done', False)
    pack_op_done = result.get('pack_op_done', False)
    ship_op_done = result.get('ship_op_done', False)
    picking_count = result.get('picking_count', 0)
    done_pickings = result.get('done_pickings', 0)

    # Do-nothing detection
    if not so_id and delivery_steps == 'ship_only' and done_pickings == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No changes detected — agent made no progress on this task"
        }

    # Criterion 1: Warehouse configured for 3-step delivery (20 pts)
    if delivery_steps == 'pick_pack_ship':
        score += 20
        subscores['warehouse_3step'] = True
        feedback_parts.append("Warehouse configured for 3-step delivery (pick_pack_ship) (+20)")
    else:
        subscores['warehouse_3step'] = False
        feedback_parts.append(f"Warehouse still on {delivery_steps!r} — expected pick_pack_ship")

    # Criterion 2: Sales order created for TechSource Procurement LLC (15 pts)
    if so_id:
        score += 15
        subscores['so_created'] = True
        feedback_parts.append(
            f"Sales order created: {result.get('so_name', '')} (state={so_state}) (+15)"
        )
    else:
        subscores['so_created'] = False
        feedback_parts.append("No sales order found for TechSource Procurement LLC")

    # Criterion 3: Pick operation completed (15 pts)
    if pick_op_done:
        score += 15
        subscores['pick_done'] = True
        feedback_parts.append("Pick operation completed (+15)")
    else:
        subscores['pick_done'] = False
        feedback_parts.append("Pick operation not completed")

    # Criterion 4: Pack operation completed (15 pts)
    if pack_op_done:
        score += 15
        subscores['pack_done'] = True
        feedback_parts.append("Pack operation completed (+15)")
    else:
        subscores['pack_done'] = False
        feedback_parts.append("Pack operation not completed")

    # Criterion 5: Ship/delivery operation completed (20 pts)
    if ship_op_done:
        score += 20
        subscores['ship_done'] = True
        feedback_parts.append("Delivery/ship operation completed (+20)")
    else:
        subscores['ship_done'] = False
        feedback_parts.append("Delivery/ship operation not completed")

    # Criterion 6: Correct quantities shipped (15 pts)
    if ship_op_done:
        qty_checks = []
        total_qty_shipped = result.get('total_qty_shipped', 0)
        expected_total = sum(p['qty'] for p in expected_products.values())

        all_qtys_correct = True
        for code, prod_info in expected_products.items():
            shipped = result.get(f'qty_shipped_{code}', 0.0)
            expected_qty = prod_info['qty']
            correct = abs(shipped - expected_qty) < 0.5
            if not correct:
                all_qtys_correct = False
            qty_checks.append(f"{code}: shipped={shipped:.0f} (expected {expected_qty})")

        if all_qtys_correct:
            score += 15
            subscores['correct_quantities'] = True
            feedback_parts.append(
                f"Correct quantities shipped: {', '.join(qty_checks)} (+15)"
            )
        else:
            subscores['correct_quantities'] = False
            feedback_parts.append(
                f"Incorrect quantities: {', '.join(qty_checks)}"
            )
    else:
        subscores['correct_quantities'] = False
        feedback_parts.append("Quantities not verified — ship not completed")

    score = max(0, score)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No actions detected",
        "subscores": subscores,
        "debug": {
            "delivery_steps": delivery_steps,
            "so_id": so_id,
            "picking_count": picking_count,
            "done_pickings": done_pickings,
            "pick_done": pick_op_done,
            "pack_done": pack_op_done,
            "ship_done": ship_op_done,
        }
    }
