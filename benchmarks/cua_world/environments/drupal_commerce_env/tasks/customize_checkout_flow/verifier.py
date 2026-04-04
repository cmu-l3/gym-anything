#!/usr/bin/env python3
"""
Verifier for customize_checkout_flow task in Drupal Commerce.

Verifies:
1. Checkout flow label was renamed to "Express Checkout"
2. Coupon redemption pane is enabled and in "order_information" step
3. Order summary pane is enabled and in "review" step
4. Completion message text matches the requirement
5. Configuration was actually modified (anti-gaming)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_checkout_flow(traj, env_info, task_info):
    """
    Verify the checkout flow configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expectations from metadata
    metadata = task_info.get('metadata', {})
    expected_label = metadata.get('expected_label', 'Express Checkout').lower()
    expected_coupon_step = metadata.get('expected_coupon_step', 'order_information')
    expected_summary_step = metadata.get('expected_summary_step', 'review')
    expected_message_part = "Thank you for shopping at Urban Electronics".lower()

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Extract configuration
    config = result.get('final_configuration', {})
    panes = config.get('configuration', {}).get('panes', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Verify Configuration Changed (Anti-gaming) - 10 points
    if result.get('config_changed', False):
        score += 10
        feedback_parts.append("Configuration was modified")
    else:
        feedback_parts.append("No configuration changes detected")

    # 2. Verify Label (Rename) - 20 points
    actual_label = config.get('label', '').lower()
    if actual_label == expected_label:
        score += 20
        feedback_parts.append(f"Label correct: '{config.get('label')}'")
    elif expected_label in actual_label:
        score += 10 # Partial credit for close match
        feedback_parts.append(f"Label close match: '{config.get('label')}'")
    else:
        feedback_parts.append(f"Label incorrect: expected 'Express Checkout', got '{config.get('label')}'")

    # 3. Verify Coupon Pane (Enable + Move) - 25 points
    coupon_pane = panes.get('coupon_redemption', {})
    coupon_step = coupon_pane.get('step', 'disabled')
    
    if coupon_step == expected_coupon_step:
        score += 25
        feedback_parts.append("Coupon pane correctly placed in Order Information")
    elif coupon_step != 'disabled':
        score += 10 # Enabled but wrong step
        feedback_parts.append(f"Coupon pane enabled but in wrong step: '{coupon_step}'")
    else:
        feedback_parts.append("Coupon pane disabled or missing")

    # 4. Verify Order Summary Pane (Enable + Move) - 25 points
    summary_pane = panes.get('order_summary', {})
    summary_step = summary_pane.get('step', 'disabled')
    
    if summary_step == expected_summary_step:
        score += 25
        feedback_parts.append("Order Summary pane correctly placed in Review")
    elif summary_step != 'disabled':
        score += 10 # Enabled but wrong step
        feedback_parts.append(f"Order Summary pane enabled but in wrong step: '{summary_step}'")
    else:
        feedback_parts.append("Order Summary pane disabled or missing")

    # 5. Verify Completion Message - 20 points
    # The message is nested deep in the completion_message pane config
    message_pane = panes.get('completion_message', {})
    message_value = message_pane.get('configuration', {}).get('message', {}).get('value', '')
    
    # Fallback to database check signal if JSON parsing fails/structure differs
    db_message_found = result.get('db_message_found', False)
    
    if expected_message_part in message_value.lower():
        score += 20
        feedback_parts.append("Completion message updated correctly")
    elif db_message_found:
        score += 20
        feedback_parts.append("Completion message verified via DB check")
    else:
        feedback_parts.append("Completion message does not contain expected text")

    # Final Evaluation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }