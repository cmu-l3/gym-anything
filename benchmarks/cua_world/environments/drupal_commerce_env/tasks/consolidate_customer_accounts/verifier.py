#!/usr/bin/env python3
"""
Verifier for consolidate_customer_accounts task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_customer_accounts(traj, env_info, task_info):
    """
    Verify order reassignment and user blocking.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        feedback_parts = []
        
        # Parse result data
        uid_old = int(result.get("uid_old", 0))
        uid_new = int(result.get("uid_new", 0))
        current_order_uid = int(result.get("current_order_uid", -1))
        old_user_exists = result.get("old_user_exists", False)
        # Convert string bool from json helper if needed
        if isinstance(old_user_exists, str):
            old_user_exists = old_user_exists.lower() == 'true'
            
        old_user_status = int(result.get("old_user_status", -1))
        new_user_status = int(result.get("new_user_status", 0))
        order_exists = result.get("order_exists", False)
        if isinstance(order_exists, str):
            order_exists = order_exists.lower() == 'true'

        # Criterion 1: Order exists (10 pts)
        if order_exists:
            score += 10
            feedback_parts.append("Order #1 still exists")
        else:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Order #1 was deleted or not found. It should be preserved."
            }

        # Criterion 2: Order reassigned to new user (40 pts)
        if current_order_uid == uid_new:
            score += 40
            feedback_parts.append("Order correctly reassigned to Sarah Jenkins")
        elif current_order_uid == uid_old:
            feedback_parts.append("Order is still assigned to Sarah Old")
        else:
            feedback_parts.append(f"Order assigned to unknown UID: {current_order_uid}")

        # Criterion 3: Old user blocked (30 pts)
        # Status 0 means blocked/inactive in Drupal
        if old_user_exists:
            if old_user_status == 0:
                score += 30
                feedback_parts.append("Old account 'sarah.old' is blocked")
            elif old_user_status == 1:
                feedback_parts.append("Old account 'sarah.old' is still active")
            else:
                feedback_parts.append(f"Old account has unknown status: {old_user_status}")
        else:
            feedback_parts.append("Old account was deleted (should have been blocked)")
            
        # Criterion 4: Old user preserved (not deleted) (10 pts)
        if old_user_exists:
            score += 10
            feedback_parts.append("Old account preserved")
            
        # Criterion 5: New user active (10 pts)
        if new_user_status == 1:
            score += 10
            feedback_parts.append("New account 'sarah.jenkins' remains active")
        else:
            feedback_parts.append("New account is not active")

        passed = (score >= 80)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}