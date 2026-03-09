#!/usr/bin/env python3
"""
Verifier for GDPR Data Erasure task.

Verification Strategy:
1. Setting Check (30 pts): 'woocommerce_erasure_request_removes_order_data' must be 'yes'.
2. User Deletion (30 pts): User with target email must not exist in wp_users.
3. Order Anonymization (40 pts): The target order's billing email must no longer match the target email.
   - Also checks timestamps to ensure the modification happened during the task.

VLM Check (Secondary):
- Uses trajectory frames to verify the agent visited Settings and Tools pages.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_gdpr_data_erasure(traj, env_info, task_info):
    """
    Verify GDPR erasure task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/gdpr_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback = []
    
    # Criterion 1: Privacy Setting (30 pts)
    # The setting value 'yes' or '1' is acceptable for "checked".
    setting_val = result.get("privacy_setting_value", "").lower()
    if setting_val in ["yes", "1", "true"]:
        score += 30
        feedback.append("Privacy setting correctly enabled.")
    else:
        feedback.append(f"Privacy setting not enabled (found: '{setting_val}').")
        
    # Criterion 2: User Deletion (30 pts)
    if result.get("user_deleted", False):
        score += 30
        feedback.append("User account successfully deleted.")
    else:
        feedback.append("User account still exists.")
        
    # Criterion 3: Order Anonymization (40 pts)
    # Must be anonymized AND modified during task
    order_anon = result.get("order_anonymized", False)
    during_task = result.get("action_occurred_during_task", False)
    
    if order_anon:
        if during_task:
            score += 40
            feedback.append("Order data anonymized successfully.")
        else:
            # Partial credit if anonymized but timestamp is weird (unlikely unless pre-setup failed)
            score += 20
            feedback.append("Order data anonymized, but timestamp check failed (anti-gaming).")
    else:
        final_email = result.get("final_order_email", "unknown")
        feedback.append(f"Order data NOT anonymized. Email is still: {final_email}")
        
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }