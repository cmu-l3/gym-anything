#!/usr/bin/env python3
"""Verifier for Gift Message Workflow task in Magento.

Task: Enable gift messages in config, then place order with specific message.

Criteria:
1. Config 'sales/gift_options/allow_order' is enabled (20 pts)
2. New order placed for test.gift@example.com (20 pts)
3. Order has a valid gift_message_id (20 pts)
4. Sender/Recipient match 'Bob'/'Alice' (20 pts)
5. Message text contains required keywords (20 pts)

Pass threshold: 80 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_gift_message_workflow(traj, env_info, task_info):
    """Verify gift message configuration and order placement."""
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_sender = metadata.get('expected_sender', 'Bob')
    expected_recipient = metadata.get('expected_recipient', 'Alice')
    keywords = metadata.get('expected_message_keywords', ['Happy Birthday', 'Enjoy the new laptop'])

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/gift_message_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    
    # 1. Config Check (20 pts)
    config_val = str(result.get('config_value', '0')).strip()
    if config_val == '1':
        score += 20
        feedback_parts.append("Config 'Allow Gift Messages on Order Level' enabled (20 pts)")
    else:
        feedback_parts.append(f"Config disabled (val={config_val})")

    # 2. Order Placed Check (20 pts)
    order_found = result.get('order_found', False)
    count_increased = result.get('order_count_increased', False)
    
    if order_found and count_increased:
        score += 20
        feedback_parts.append("New order placed successfully (20 pts)")
    elif order_found:
        score += 10
        feedback_parts.append("Order found but count didn't increase? (Possible pre-existing order) (10 pts)")
    else:
        feedback_parts.append("No order found for test.gift@example.com")

    # 3. Message Attached Check (20 pts)
    # gift_message_id can be 'NULL' string from bash export or actual None
    msg_id = result.get('gift_message_id')
    has_message = msg_id and str(msg_id).lower() != 'null' and str(msg_id).strip() != ''
    
    if has_message:
        score += 20
        feedback_parts.append("Order has gift message attached (20 pts)")
    else:
        feedback_parts.append("Order does not have a gift message attached")

    # 4. Sender/Recipient Check (20 pts)
    sender = result.get('message_sender', '').strip()
    recipient = result.get('message_recipient', '').strip()
    
    sender_ok = expected_sender.lower() in sender.lower()
    recipient_ok = expected_recipient.lower() in recipient.lower()
    
    if sender_ok and recipient_ok:
        score += 20
        feedback_parts.append(f"Sender/Recipient match ({sender}/{recipient}) (20 pts)")
    elif sender_ok or recipient_ok:
        score += 10
        feedback_parts.append(f"Partial match on names (Sender: {sender}, Recipient: {recipient}) (10 pts)")
    else:
        if has_message:
            feedback_parts.append(f"Names mismatch (Got: {sender} -> {recipient})")

    # 5. Message Text Check (20 pts)
    msg_text = result.get('message_text', '').lower()
    keywords_found = [k for k in keywords if k.lower() in msg_text]
    
    if len(keywords_found) == len(keywords):
        score += 20
        feedback_parts.append("Message text correct (20 pts)")
    elif len(keywords_found) > 0:
        score += 10
        feedback_parts.append(f"Message text partial match. Found: {keywords_found} (10 pts)")
    else:
        if has_message:
            feedback_parts.append(f"Message text mismatch. Got: '{result.get('message_text')}'")

    pass_threshold = 80
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }