#!/usr/bin/env python3
"""Verifier for Social Sharing Configuration task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_social_sharing_config(traj, env_info, task_info):
    """
    Verify Magento configuration settings for social sharing.

    Criteria:
    1. Email to a Friend Enabled (20 pts)
    2. Guest Access Disabled (15 pts)
    3. Max Recipients = 3 (15 pts)
    4. Max Per Hour = 5 (15 pts)
    5. Wishlist Share Limit = 5 (15 pts)
    6. Wishlist Email Sender = Customer Support (20 pts)

    Pass threshold: 70 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_configs', {
        "sendfriend/email/enabled": "1",
        "sendfriend/email/allow_guest": "0",
        "sendfriend/email/max_recipients": "3",
        "sendfriend/email/max_per_hour": "5",
        "wishlist/email/number_limit": "5",
        "wishlist/email/email_identity": "support"
    })

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/social_config_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    config = result.get('config', {})
    logger.info(f"Retrieved config: {config}")

    score = 0
    feedback_parts = []
    
    # 1. Email to a Friend Enabled (20 pts)
    # Value '1' is Enabled
    val_enabled = str(config.get('sendfriend/email/enabled', '0'))
    if val_enabled == '1':
        score += 20
        feedback_parts.append("Email to a Friend enabled (20/20)")
    else:
        feedback_parts.append(f"Email to a Friend NOT enabled (Found: {val_enabled})")

    # 2. Guest Access Disabled (15 pts)
    # Value '0' is No
    val_guest = str(config.get('sendfriend/email/allow_guest', '1'))
    if val_guest == '0':
        score += 15
        feedback_parts.append("Guest access disabled (15/15)")
    else:
        feedback_parts.append(f"Guest access NOT disabled (Found: {val_guest})")

    # 3. Recipient Limit (15 pts)
    val_recipients = str(config.get('sendfriend/email/max_recipients', ''))
    if val_recipients == '3':
        score += 15
        feedback_parts.append("Max recipients set to 3 (15/15)")
    else:
        feedback_parts.append(f"Max recipients incorrect (Found: '{val_recipients}', Expected: '3')")

    # 4. Hourly Limit (15 pts)
    val_hourly = str(config.get('sendfriend/email/max_per_hour', ''))
    if val_hourly == '5':
        score += 15
        feedback_parts.append("Hourly limit set to 5 (15/15)")
    else:
        feedback_parts.append(f"Hourly limit incorrect (Found: '{val_hourly}', Expected: '5')")

    # 5. Wishlist Share Limit (15 pts)
    val_wishlist_limit = str(config.get('wishlist/email/number_limit', ''))
    if val_wishlist_limit == '5':
        score += 15
        feedback_parts.append("Wishlist share limit set to 5 (15/15)")
    else:
        feedback_parts.append(f"Wishlist share limit incorrect (Found: '{val_wishlist_limit}', Expected: '5')")

    # 6. Wishlist Sender Identity (20 pts)
    val_wishlist_sender = str(config.get('wishlist/email/email_identity', ''))
    if val_wishlist_sender == 'support':
        score += 20
        feedback_parts.append("Wishlist sender set to 'Customer Support' (20/20)")
    else:
        feedback_parts.append(f"Wishlist sender incorrect (Found: '{val_wishlist_sender}', Expected: 'support')")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }