#!/usr/bin/env python3
"""Verifier for Store Operations Config task in Magento.

Task: Update configuration settings for Persistent Cart, Newsletter, Contact Us, and Wishlist.

Criteria:
1. Persistent Cart Enabled (10 pts)
2. Persistent Lifetime is exactly 30 days (2,592,000 seconds) (30 pts)
3. Remember Me Enabled (10 pts)
4. Clear Persistence on Sign Out is NO (5 pts)
5. Persist Shopping Cart is YES (5 pts)
6. Guest Subscription Allowed (20 pts)
7. Contact Email is 'support@luma.com' (10 pts)
8. Wishlist is Disabled (10 pts)

Pass threshold: 60 pts (Requires Lifetime calculation + some other correct settings)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_store_operations_config(traj, env_info, task_info):
    """
    Verify configuration changes in Magento.
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_lifetime = int(metadata.get('expected_lifetime_seconds', 2592000))
    expected_email = metadata.get('expected_contact_email', 'support@luma.com').lower()

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/store_config_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []

    # 1. Persistent Cart (Enabled) - 10 pts
    p_enabled = str(result.get('persistent_enabled', '0')) == '1'
    if p_enabled:
        score += 10
        feedback_parts.append("Persistent Cart Enabled (10 pts)")
    else:
        feedback_parts.append("Persistent Cart NOT enabled")

    # 2. Lifetime (30 days = 2592000 seconds) - 30 pts
    lifetime_val = 0
    try:
        lifetime_val = int(result.get('persistent_lifetime', '0'))
    except ValueError:
        pass
    
    if lifetime_val == expected_lifetime:
        score += 30
        feedback_parts.append(f"Lifetime correct: {lifetime_val}s (30 pts)")
    else:
        feedback_parts.append(f"Lifetime incorrect: expected {expected_lifetime}, got {lifetime_val}")

    # 3. Remember Me (Enabled) - 10 pts
    r_enabled = str(result.get('remember_enabled', '0')) == '1'
    if r_enabled:
        score += 10
        feedback_parts.append("Remember Me Enabled (10 pts)")
    else:
        feedback_parts.append("Remember Me NOT enabled")
        
    # 4. Clear on Sign Out (No=0) - 5 pts
    # Note: Logic in Magento is "Clear on Logout" -> No means 0
    logout_clear = str(result.get('logout_clear', '1')) == '0'
    if logout_clear:
        score += 5
        feedback_parts.append("Clear on Sign Out is NO (5 pts)")
    else:
        feedback_parts.append("Clear on Sign Out is YES (expected NO)")

    # 5. Persist Shopping Cart (Yes=1) - 5 pts
    persist_cart = str(result.get('persist_shopping_cart', '0')) == '1'
    if persist_cart:
        score += 5
        feedback_parts.append("Persist Shopping Cart is YES (5 pts)")
    else:
        feedback_parts.append("Persist Shopping Cart is NO (expected YES)")

    # 6. Guest Subscription (Allowed) - 20 pts
    g_sub = str(result.get('allow_guest_subscribe', '0')) == '1'
    if g_sub:
        score += 20
        feedback_parts.append("Guest Subscription Allowed (20 pts)")
    else:
        feedback_parts.append("Guest Subscription NOT allowed")

    # 7. Contact Email - 10 pts
    c_email = str(result.get('contact_email', '')).strip().lower()
    if c_email == expected_email:
        score += 10
        feedback_parts.append(f"Contact email correct: {c_email} (10 pts)")
    else:
        feedback_parts.append(f"Contact email incorrect: expected {expected_email}, got '{c_email}'")

    # 8. Wishlist (Disabled) - 10 pts
    w_active = str(result.get('wishlist_active', '1')) == '0'
    if w_active:
        score += 10
        feedback_parts.append("Wishlist Disabled (10 pts)")
    else:
        feedback_parts.append("Wishlist is Enabled (expected Disabled)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }