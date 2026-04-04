#!/usr/bin/env python3
"""
Verifier for Implement B2B Net 30 Payment task.

Scoring:
- Role Created: 10 pts
- User Created: 10 pts
- Role Assigned: 10 pts
- Gateway Exists: 20 pts
- Plugin Correct (Manual): 10 pts
- Instructions Correct: 20 pts
- Condition Logic Correct: 20 pts

Pass Threshold: 70 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_b2b_net30_payment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 1. Role Created (10 pts)
    if result.get('role_found'):
        score += 10
        feedback_parts.append("Role 'Wholesale Buyer' found")
    else:
        feedback_parts.append("Role 'Wholesale Buyer' NOT found")

    # 2. User Created (10 pts)
    if result.get('user_found'):
        score += 10
        feedback_parts.append("User 'corporate_buyer' found")
    else:
        feedback_parts.append("User 'corporate_buyer' NOT found")

    # 3. Role Assigned (10 pts)
    if result.get('user_has_role'):
        score += 10
        feedback_parts.append("Role assigned to user correctly")
    elif result.get('user_found') and result.get('role_found'):
        feedback_parts.append("User and Role exist, but role NOT assigned to user")
    
    # 4. Gateway Exists (20 pts)
    if result.get('gateway_found'):
        score += 20
        feedback_parts.append("Net 30 Payment Gateway found")
    else:
        feedback_parts.append("Net 30 Payment Gateway NOT found")

    # 5. Plugin Correct (10 pts)
    plugin = result.get('gateway_plugin', '')
    if plugin == 'manual':
        score += 10
        feedback_parts.append("Gateway uses 'Manual' plugin")
    elif result.get('gateway_found'):
        feedback_parts.append(f"Gateway uses incorrect plugin: '{plugin}'")

    # 6. Instructions Correct (20 pts)
    if result.get('instructions_correct'):
        score += 20
        feedback_parts.append("Payment instructions correct")
    elif result.get('gateway_found'):
        feedback_parts.append("Payment instructions do not match requirements")

    # 7. Condition Logic (20 pts)
    if result.get('condition_correct'):
        score += 20
        feedback_parts.append("Condition 'Customer Role' configured correctly")
    elif result.get('gateway_found'):
        feedback_parts.append("Gateway condition missing or incorrect")

    passed = score >= 70 and result.get('gateway_found') and result.get('role_found') and result.get('condition_correct')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }