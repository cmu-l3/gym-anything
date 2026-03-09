#!/usr/bin/env python3
"""Verifier for Inventory Scarcity Config task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_inventory_scarcity_config(traj, env_info, task_info):
    """
    Verify global inventory configuration settings.
    
    Criteria:
    1. Backorders enabled with notification (Value 2) - 30 pts
    2. Scarcity threshold set to 5 - 25 pts
    3. Show Out of Stock products enabled (Value 1) - 20 pts
    4. Stock Alerts enabled (Value 1) - 25 pts
    
    Pass threshold: 75 points.
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/inventory_config_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result: {result}")
    
    final_config = result.get('final', {})
    initial_config = result.get('initial', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Backorders: Expect '2' (Allow Qty Below 0 and Notify Customer)
    # Value '1' is just "Allow Qty Below 0", which is incorrect for this task.
    backorders_val = str(final_config.get('backorders', '')).strip()
    if backorders_val == '2':
        score += 30
        feedback_parts.append("Backorders set to 'Allow & Notify' (30 pts)")
    elif backorders_val == '1':
        score += 10
        feedback_parts.append("Backorders set to 'Allow' but missing 'Notify Customer' (10 pts partial)")
    else:
        feedback_parts.append(f"Backorders incorrect (expected 2, got {backorders_val})")

    # 2. Scarcity Threshold: Expect '5'
    threshold_val = str(final_config.get('threshold', '')).strip()
    # Normalize potential float strings e.g. "5.0000"
    try:
        threshold_float = float(threshold_val)
        if abs(threshold_float - 5.0) < 0.01:
            score += 25
            feedback_parts.append("Scarcity threshold set to 5 (25 pts)")
        else:
            feedback_parts.append(f"Threshold incorrect (expected 5, got {threshold_float})")
    except ValueError:
        feedback_parts.append(f"Threshold value invalid or unset")

    # 3. Show Out of Stock: Expect '1' (Yes)
    show_oos_val = str(final_config.get('show_out_of_stock', '')).strip()
    if show_oos_val == '1':
        score += 20
        feedback_parts.append("Show Out of Stock products enabled (20 pts)")
    else:
        feedback_parts.append("Show Out of Stock products NOT enabled")

    # 4. Stock Alerts: Expect '1' (Yes)
    alerts_val = str(final_config.get('allow_alert', '')).strip()
    if alerts_val == '1':
        score += 25
        feedback_parts.append("Stock Alerts enabled (25 pts)")
    else:
        feedback_parts.append("Stock Alerts NOT enabled")

    # Anti-gaming check: Ensure at least one value changed from initial
    changed = False
    if backorders_val != str(initial_config.get('backorders', '')): changed = True
    if threshold_val != str(initial_config.get('threshold', '')): changed = True
    if show_oos_val != str(initial_config.get('show_out_of_stock', '')): changed = True
    if alerts_val != str(initial_config.get('allow_alert', '')): changed = True
    
    if not changed and score > 0:
        feedback_parts.append("(WARNING: No configuration changes detected from initial state)")
        # In a real anti-gaming scenario, we might zero the score, 
        # but here we'll assume the environment starts with defaults (0) and task requires non-defaults.
        # If the environment happened to start with the target state, the agent 'did nothing' but the state is correct.
        # However, defaults are typically 0/No, so changes are expected.

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }